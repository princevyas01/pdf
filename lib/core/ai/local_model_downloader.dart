import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalModelDescriptor {
  final String id;
  final String name;
  final String fileName;
  final String url;
  final int? expectedSizeBytes;
  final String displaySize;
  final String sha256;
  final String license;
  final String description;

  const LocalModelDescriptor({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.expectedSizeBytes,
    required this.displaySize,
    required this.sha256,
    required this.license,
    required this.description,
  });

  double? get sizeMb => expectedSizeBytes == null
      ? null
      : expectedSizeBytes! / (1024 * 1024);
}

class LocalModelDownloadException implements Exception {
  final String message;
  const LocalModelDownloadException(this.message);

  @override
  String toString() => message;
}

class LocalModelDownloader {
  static const models = <LocalModelDescriptor>[
    LocalModelDescriptor(
      id: 'qwen3-4b-q4km',
      name: 'Qwen3 4B Q4_K_M',
      fileName: 'Qwen3-4B-Q4_K_M.gguf',
      url:
          'https://huggingface.co/ggml-org/Qwen3-4B-GGUF/resolve/2f3b082b1356a6123f7ed71e65aea340da25d53c/Qwen3-4B-Q4_K_M.gguf',
      expectedSizeBytes: 2497280640,
      displaySize: '~2.50 GB',
      sha256:
          'ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328',
      license: 'Apache-2.0',
      description:
          'Primary study model for document explanations, revision notes and exam generation.',
    ),
    LocalModelDescriptor(
      id: 'qwen3-0.6b-q40',
      name: 'Qwen3 0.6B Q4_0',
      fileName: 'Qwen3-0.6B-Q4_0.gguf',
      url:
          'https://huggingface.co/ggml-org/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf',
      expectedSizeBytes: null,
      displaySize: '~429 MB',
      sha256:
          'da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4',
      license: 'Apache-2.0',
      description:
          'Lower-memory quick model for shorter answers and lighter devices.',
    ),
  ];

  static Future<Directory> _modelDirectory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'local_ai_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> modelFile(LocalModelDescriptor model) async {
    final dir = await _modelDirectory();
    return File(p.join(dir.path, model.fileName));
  }

  static Future<File> partialFile(LocalModelDescriptor model) async {
    final dir = await _modelDirectory();
    return File(p.join(dir.path, '${model.fileName}.part'));
  }

  static Future<File> verifiedFile(LocalModelDescriptor model) async {
    final dir = await _modelDirectory();
    return File(p.join(dir.path, '${model.fileName}.verified.json'));
  }

  static Future<bool> isInstalled(LocalModelDescriptor model) async {
    final target = await modelFile(model);
    final marker = await verifiedFile(model);
    if (!await target.exists() || !await marker.exists()) return false;
    try {
      final stat = await target.stat();
      final raw = jsonDecode(await marker.readAsString());
      return raw is Map &&
          raw['modelId'] == model.id &&
          raw['sha256'] == model.sha256 &&
          raw['sizeBytes'] == stat.size;
    } catch (_) {
      return false;
    }
  }

  static Future<void> download(
    LocalModelDescriptor model, {
    required void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final target = await modelFile(model);
    final partial = await partialFile(model);
    final marker = await verifiedFile(model);
    var received = await partial.exists() ? await partial.length() : 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30);

    try {
      final request = await client.getUrl(Uri.parse(model.url));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (received > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$received-');
      }
      final response = await request.close();
      if (received > 0) {
        if (response.statusCode == HttpStatus.partialContent) {
          final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
          final expectedPrefix = 'bytes $received-';
          if (contentRange == null || !contentRange.startsWith(expectedPrefix)) {
            await response.drain<void>();
            throw const LocalModelDownloadException(
              'Server returned an unexpected Content-Range for the resumed download.',
            );
          }
        } else if (response.statusCode == HttpStatus.ok) {
          await partial.writeAsBytes(const [], flush: true);
          received = 0;
        } else {
          throw LocalModelDownloadException(
            'Model resume failed: HTTP ${response.statusCode}.',
          );
        }
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw LocalModelDownloadException(
          'Model download failed: HTTP ${response.statusCode}.',
        );
      }

      final contentLength = response.contentLength;
      final total = model.expectedSizeBytes ??
          (received + (contentLength > 0 ? contentLength : 0));
      var current = received;
      final sink = partial.openWrite(
        mode: received > 0 ? FileMode.append : FileMode.write,
      );

      try {
        await for (final chunk in response) {
          if (isCancelled?.call() ?? false) {
            throw const LocalModelDownloadException(
              'Download cancelled. Partial file retained for resume.',
            );
          }
          sink.add(chunk);
          current += chunk.length;
          onProgress(current, total);
        }
      } finally {
        await sink.close();
      }

      if (current <= 0) {
        throw const LocalModelDownloadException('Downloaded model file is empty.');
      }

      final digest = await _sha256(partial);
      if (digest != model.sha256) {
        await partial.delete();
        if (await marker.exists()) await marker.delete();
        throw const LocalModelDownloadException(
          'SHA-256 verification failed. The model was deleted.',
        );
      }

      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      await marker.writeAsString(jsonEncode({
        'modelId': model.id,
        'sha256': model.sha256,
        'sizeBytes': await target.length(),
        'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
      }), flush: true);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _sha256(File file) async {
    final digest = await file.openRead().transform(sha256).first;
    return digest.toString();
  }

  static Future<void> delete(LocalModelDescriptor model) async {
    final target = await modelFile(model);
    final partial = await partialFile(model);
    final marker = await verifiedFile(model);
    for (final file in [target, partial, marker]) {
      if (await file.exists()) await file.delete();
    }
  }
}
