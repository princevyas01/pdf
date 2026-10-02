// lib/core/ai/local_llm_service.dart
// Replace the entire file with this implementation.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'ai_model_manager.dart';
import 'local_model_downloader.dart';

class ContextHelper {
  final int contextSize;
  const ContextHelper({required this.contextSize});

  int estimateTokens(String text) => (text.length / 3.5).ceil();

  int calculateSafeMaxTokens(int promptTokens, int requestedOutput) {
    final available = contextSize - promptTokens - 32;
    return min(available, requestedOutput);
  }
}

class LocalLlmMemoryException implements Exception {
  final String message;
  const LocalLlmMemoryException(this.message);
  @override
  String toString() => 'LocalLlmMemoryException: $message';
}

class LocalLlmException implements Exception {
  final String message;
  const LocalLlmException(this.message);
  @override
  String toString() => message;
}

class LocalLlmService {
  LocalLlmService._();
  static final LocalLlmService instance = LocalLlmService._();

  LlamaController? _controller;
  StreamSubscription<String>? _generationSubscription;
  bool _loaded = false;
  String? _loadedModelId;
  int _activeContextSize = 1024;

  // One queue for the entire native-controller lifecycle.
  Future<void> _operationTail = Future<void>.value();

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<LocalModelDescriptor?> _resolveInstalledModel() async {
    await AiModelManager.instance.initialize();
    final modelId = AiModelManager.instance.installedModelId ??
        (LocalModelDownloader.models.isNotEmpty
            ? LocalModelDownloader.models.first.id
            : null);
    if (modelId == null || modelId.isEmpty) return null;
    const models = LocalModelDownloader.models;
    for (final model in models) {
      if (model.id != modelId) continue;
      final installed = await LocalModelDownloader.isInstalled(model);
      if (!installed) return null;
      return model;
    }
    return null;
  }

  Future<void> _disposeControllerLocked() async {
    await _generationSubscription?.cancel();
    _generationSubscription = null;

    final controller = _controller;
    _controller = null;
    _loaded = false;
    _loadedModelId = null;

    if (controller != null) {
      try {
        await controller.stop();
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _loadLocked() async {
    final model = await _resolveInstalledModel();
    if (model == null) {
      throw StateError('No verified local AI model is installed.');
    }

    if (_loaded && _controller != null && _loadedModelId == model.id) {
      return;
    }

    if (_controller != null || _loaded) {
      await _disposeControllerLocked();
    }

    final controller = LlamaController();
    try {
      final gpuInfo = await controller.detectGpu();
      final freeRam = gpuInfo.freeRamBytes;
      final expectedSize = model.expectedSizeBytes ?? 2497280640;
      final requiredFloor = expectedSize + (1024 * 1024 * 1024);

      // Do not enter native inference when the device is already under pressure.
      if (model.id.contains('4b') && freeRam > 0 && freeRam < requiredFloor) {
        await controller.dispose();
        throw LocalLlmMemoryException(
          'Insufficient free RAM for the selected 4B model. '
          'Free RAM: ${freeRam ~/ (1024 * 1024)} MB; '
          'minimum safety floor: ${requiredFloor ~/ (1024 * 1024)} MB.',
        );
      }

      int gpuLayers = 0;
      final recommended = gpuInfo.recommendedGpuLayers;
      if (gpuInfo.vulkanSupported && recommended > 0) {
        gpuLayers = min(recommended, 16);
      }

      int targetContext = 1024;
      if (!model.id.contains('4b')) {
        targetContext = 1024;
      }
      _activeContextSize = targetContext;

      final file = await LocalModelDownloader.modelFile(model);
      await controller.loadModel(
        modelPath: file.path,
        contextSize: targetContext,
        gpuLayers: gpuLayers,
        threads: 2,
      );

      _controller = controller;
      _loaded = true;
      _loadedModelId = model.id;
    } catch (_) {
      try {
        await controller.stop();
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> load() => _runExclusive(_loadLocked);

  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int? maxTokens,
    double temperature = 0.2,
    double topP = 0.9,
  }) =>
      _runExclusive(() async {
        await _loadLocked();
        final controller = _controller;
        if (controller == null || !_loaded) {
          throw StateError('Local LLM controller is not available.');
        }

        await _generationSubscription?.cancel();
        _generationSubscription = null;

        await controller.clearContext();

        final helper = ContextHelper(contextSize: _activeContextSize);
        final requestedOutput = (maxTokens ?? 256).clamp(96, 192).toInt();
        final safeOutput = helper
            .calculateSafeMaxTokens(0, requestedOutput)
            .clamp(64, 192)
            .toInt();

        const systemCharsMax = 1200;
        final safeSystem = systemPrompt.length > systemCharsMax
            ? systemPrompt.substring(0, systemCharsMax)
            : systemPrompt;

        final baseOverheadTokens = helper.estimateTokens(safeSystem) + 64;
        final remaining =
            max(64, _activeContextSize - safeOutput - baseOverheadTokens - 32);
        final safeUser = _trimToTokenBudget(userPrompt, helper, remaining);

        final messages = <ChatMessage>[
          ChatMessage(role: 'system', content: safeSystem),
          ChatMessage(role: 'user', content: safeUser),
        ];

        controller.setSystemPromptLength(safeSystem.length);

        final buffer = StringBuffer();
        final completer = Completer<String>();
        try {
          final stream = controller.generateChat(
            messages: messages,
            template: 'chatml',
            temperature: temperature,
            topP: topP,
            maxTokens: safeOutput,
          );

          _generationSubscription = stream.listen(
            (token) => buffer.write(token),
            onError: (Object error, StackTrace stack) {
              if (!completer.isCompleted) completer.completeError(error, stack);
            },
            onDone: () {
              if (!completer.isCompleted) {
                completer.complete(buffer.toString().trim());
              }
            },
            cancelOnError: true,
          );

          final rawText = await completer.future.timeout(
            const Duration(seconds: 120),
            onTimeout: () =>
                throw TimeoutException('Local LLM generation timed out.'),
          );
          return _cleanModelText(rawText);
        } finally {
          await _generationSubscription?.cancel();
          _generationSubscription = null;
          try {
            await controller.stop();
          } catch (_) {}
        }
      });

  String _trimToTokenBudget(
      String input, ContextHelper helper, int tokenBudget) {
    if (input.isEmpty) return input;
    if (helper.estimateTokens(input) <= tokenBudget) return input;

    int low = 0;
    int high = input.length;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      final candidate = input.substring(0, mid);
      if (helper.estimateTokens(candidate) <= tokenBudget) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return input.substring(0, low);
  }

  Future<void> stop() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.stop();
    } catch (e, st) {
      debugPrint('LocalLlmService.stop: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> unload() => _runExclusive(() async {
        await _disposeControllerLocked();
      });

  bool get isLoaded => _loaded;
  int get activeContextSize => _activeContextSize;
  String? get loadedModelId => _loadedModelId;

  String _cleanModelText(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    // Strip completed think blocks
    final withoutCompleteThink = value
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '')
        .trim();
    if (withoutCompleteThink.isNotEmpty) {
      value = withoutCompleteThink;
    }
    // If thinking block was opened but not closed, strip the think open tag
    value = value.replaceAll('<think>', '').replaceAll('</think>', '').trim();
    value = value
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|endoftext|>', '')
        .replaceAll('<|im_start|>', '');
    value = value.replaceAll(
        RegExp(r'^```(?:json|text)?\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*```$'), '');
    return value.trim();
  }
}
