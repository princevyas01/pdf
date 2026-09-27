import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pdf_open_request.dart';
import '../storage/pdf_metadata_helper.dart';
import '../../features/home/pdf_list_provider.dart';
import '../../features/viewer/pdf_viewer_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ExternalPdfIntentService {
  static const MethodChannel _channel =
      MethodChannel('com.offlinepdf.app/intent');
  static final Set<String> _handledRequestIds = <String>{};

  static void initialize(WidgetRef ref) {
    // This is the SINGLE MethodChannel handler for the entire
    // com.offlinepdf.app/intent channel.
    //
    // Do not install another setMethodCallHandler() on this
    // channel from PdfListNotifier or any other widget.

    _channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'onPdfOpened':
            if (call.arguments != null) {
              final map = call.arguments as Map<dynamic, dynamic>;
              final request = PdfOpenRequest.fromMap(map);
              await _processOpenRequest(ref, request);
            }
            break;

          case 'onMediaStorePdfChanged':
            // MediaStore change notifications are also handled here
            // so the same MethodChannel has only ONE Dart handler.
            try {
              await ref
                  .read(pdfListProvider.notifier)
                  .fastDeviceSync();
            } catch (e) {
              debugPrint(
                'Fast device sync after MediaStore change failed: $e',
              );
            }
            break;

          default:
            // Ignore methods not owned by this Dart handler.
            break;
        }
      } catch (e, st) {
        debugPrint(
          'External PDF MethodChannel error: $e\n$st',
        );
      }
    });

    // Native must know that Dart is ready before dispatching
    // pending external PDF requests.
    _channel
        .invokeMethod<bool>('markIntentHandlerReady')
        .then((_) {
      return _channel
          .invokeMethod<Map<dynamic, dynamic>>(
            'getInitialPdfRequest',
          );
    }).then((map) {
      if (map != null) {
        final request = PdfOpenRequest.fromMap(map);

        // Do not allow an early external intent to crash the
        // application during startup.
        _processOpenRequest(ref, request).catchError((e, st) {
          debugPrint(
            'Failed to process initial external PDF request: '
            '$e\n$st',
          );
        });
      }
    }).catchError((e) {
      debugPrint(
        'Failed to initialize external PDF intent handling: $e',
      );
    });
  }

  static Future<void> _processOpenRequest(
      WidgetRef ref, PdfOpenRequest request) async {
    if (request.requestId.isNotEmpty &&
        _handledRequestIds.contains(request.requestId)) {
      return;
    }

    if (request.requestId.isNotEmpty) {
      _handledRequestIds.add(request.requestId);
      if (_handledRequestIds.length > 100) {
        _handledRequestIds.remove(_handledRequestIds.first);
      }
    }

    final itemsToRegister =
        request.documents.isNotEmpty ? request.documents : [request];

    String? primaryViewerPath;

    for (final doc in itemsToRegister) {
      final path = doc.localPath;
      if (path.isEmpty) continue;

      try {
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) {
          continue;
        }

        if (doc.isTemporary || path.contains('temp_external_pdfs')) {
          // Temporary stream cache: Do NOT index into persistent user library
          primaryViewerPath ??= path;
        } else {
          // Real device file: Register and sync metadata
          final registered = await PdfMetadataHelper.registerAndSyncPdf(
            path,
            displayName: doc.fileName,
          );
          if (registered != null) {
            ref.read(pdfListProvider.notifier).addFile(registered);
            primaryViewerPath ??= path;
          }
        }
      } catch (e) {
        debugPrint('Error handling intent document $path: $e');
      }
    }

    // Only run single-document fallback if documents list was empty
    if (request.documents.isEmpty &&
        primaryViewerPath == null &&
        request.localPath.isNotEmpty) {
      final file = File(request.localPath);
      if (await file.exists() && await file.length() > 0) {
        if (request.isTemporary || request.localPath.contains('temp_external_pdfs')) {
          primaryViewerPath = request.localPath;
        } else {
          final registered = await PdfMetadataHelper.registerAndSyncPdf(
            request.localPath,
            displayName: request.fileName,
          );
          if (registered != null) {
            ref.read(pdfListProvider.notifier).addFile(registered);
            primaryViewerPath = request.localPath;
          }
        }
      }
    }

    if (primaryViewerPath != null) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              filePath: primaryViewerPath!,
              isExternalLaunch: request.isExternalLaunch,
            ),
          ),
          (route) => route.isFirst,
        );
      }
    } else {
      _showErrorSnackBar(
          'Unable to read PDF document(s) from source application.');
    }
  }

  static void _showErrorSnackBar(String message) {
    final context = appNavigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }
}
