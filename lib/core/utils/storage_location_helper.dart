import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageLocationHelper {
  /// Returns a user-accessible persistent storage directory for the app.
  /// Prioritizes /storage/emulated/0/Documents/[AppName] or /storage/emulated/0/Download/[AppName]
  /// and falls back gracefully to getExternalStorageDirectory() or getApplicationDocumentsDirectory().
  static Future<Directory> getPublicDocumentsDirectory({String subFolder = 'Scans'}) async {
    if (Platform.isAndroid) {
      // 1. Try public Documents folder
      final documentsDir = Directory('/storage/emulated/0/Documents/PDF Reader/$subFolder');
      try {
        if (!await documentsDir.exists()) {
          await documentsDir.create(recursive: true);
        }
        return documentsDir;
      } catch (_) {}

      // 2. Try public Download folder
      final downloadDir = Directory('/storage/emulated/0/Download/PDF Reader/$subFolder');
      try {
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } catch (_) {}

      // 3. Try external storage directory
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final target = Directory(p.join(extDir.path, subFolder));
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          return target;
        }
      } catch (_) {}
    }

    // 4. Default fallback to app documents directory
    final appDocDir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(appDocDir.path, subFolder));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// Generates a collision-safe unique file path while preserving
  /// the extension supplied by the caller.
  static Future<String> getUniqueFilePath(
    Directory directory,
    String baseFileName,
  ) async {
    var safeName = baseFileName.trim();

    if (safeName.isEmpty) {
      safeName = 'file';
    }

    // Strip illegal filesystem characters.
    safeName = safeName.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );

    final extension = p.extension(safeName);
    final nameWithoutExtension = p.basenameWithoutExtension(safeName);

    var candidatePath = p.join(
      directory.path,
      safeName,
    );

    int counter = 1;

    while (await File(candidatePath).exists()) {
      final candidateName = extension.isEmpty
          ? '${nameWithoutExtension}_$counter'
          : '${nameWithoutExtension}_$counter$extension';

      candidatePath = p.join(
        directory.path,
        candidateName,
      );

      counter++;
    }

    return candidatePath;
  }
}
