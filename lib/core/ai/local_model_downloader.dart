import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalModelDescriptor {
  final String id;
  final String name;
  final String fileName;
  final String url;
  final int sizeBytes;
  final String sha256;
  final String license;
  final String description;

  const LocalModelDescriptor({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.license,
    required this.description,
  });

  double get sizeMb => sizeBytes / (1024 * 1024);
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
      id: 'qwen3-1.7b-q4km',
      name: 'Qwen3 1.7B Q4_K_M',
      fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
      url:
          'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/daeb8e2d528a760970442092f6bf1e55c3b659eb/Qwen3-1.7B-Q4_K_M.gguf',
      sizeBytes: 1280000000,
      sha256:
          'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5',
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
      sizeBytes: 429000000,
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

  static Future<bool> isInstalled(LocalModelDescriptor model) async {
    final file = await modelFile(model);
    if (!await file.exists()) return false;
    final stat = await file.stat();
    return stat.size == model.sizeBytes;
  }

  static Future<void> download(
    LocalModelDescriptor model, {
    required void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final target = await modelFile(model);
    final partial = await partialFile(model);
    var received = await partial.exists() ? await partial.length() : 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(model.url));
      if (received > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$received-');
      }
      final response = await request.close();
      if (received > 0 && response.statusCode != HttpStatus.partialContent) {
        await partial.writeAsBytes(const [], flush: true);
        received = 0;
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw LocalModelDownloadException(
            'Model download failed: HTTP ${response.statusCode}.');
      }
      final contentLength = response.contentLength;
      final total = received + (contentLength > 0 ? contentLength : 0);
      final sink = partial.openWrite(
          mode: received > 0 ? FileMode.append : FileMode.write);
      var current = received;
      await for (final chunk in response) {
        if (isCancelled?.call() ?? false) {
          await sink.close();
          throw const LocalModelDownloadException(
              'Download cancelled. Partial file retained for resume.');
        }
        sink.add(chunk);
        current += chunk.length;
        onProgress(current, total);
      }
      await sink.close();
      if (current != model.sizeBytes) {
        throw LocalModelDownloadException(
            'Downloaded file size is $current bytes; expected ${model.sizeBytes} bytes.');
      }
      final digest = await _sha256(partial);
      if (digest != model.sha256) {
        await partial.delete();
        throw const LocalModelDownloadException(
            'SHA-256 verification failed. The model was deleted.');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
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
    if (await target.exists()) await target.delete();
    if (await partial.exists()) await partial.delete();
  }
}
