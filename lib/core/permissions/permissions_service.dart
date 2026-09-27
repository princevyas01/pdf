import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

enum StoragePermissionState {
  granted,
  denied,
  permanentlyDenied,
  unknown,
}

class PermissionsNotifier extends StateNotifier<StoragePermissionState> {
  PermissionsNotifier() : super(StoragePermissionState.unknown) {
    checkStoragePermission();
  }

  Future<void> checkStoragePermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      state = StoragePermissionState.granted;
    } else if (status.isPermanentlyDenied) {
      state = StoragePermissionState.permanentlyDenied;
    } else if (status.isDenied) {
      state = StoragePermissionState.denied;
    } else {
      // Fallback check for storage
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        state = StoragePermissionState.granted;
      } else {
        state = StoragePermissionState.denied;
      }
    }
  }

  Future<bool> requestStoragePermission() async {
    PermissionStatus status = await Permission.manageExternalStorage.request();
    
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    if (status.isGranted) {
      state = StoragePermissionState.granted;
      return true;
    } else if (status.isPermanentlyDenied) {
      state = StoragePermissionState.permanentlyDenied;
      return false;
    } else {
      state = StoragePermissionState.denied;
      return false;
    }
  }

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }
}

final permissionsProvider =
    StateNotifierProvider<PermissionsNotifier, StoragePermissionState>((ref) {
  return PermissionsNotifier();
});
