import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'ai_model_manager.dart';
import 'local_model_downloader.dart';

class LocalLlmException implements Exception {
  final String message;
  const LocalLlmException(this.message);
  @override
  String toString() => message;
}

class LocalLlmService {
  static final LocalLlmService instance = LocalLlmService._init();
  LocalLlmService._init();

  LlamaController? _controller;
  StreamSubscription<String>? _generationSubscription;
  bool _loaded = false;
  String? _loadedModelId;
  int _activeContextSize = 1024;

  bool get isLoaded => _loaded;
  int get activeContextSize => _activeContextSize;

  Future<File?> _resolveInstalledModel() async {
    final id = AiModelManager.instance.installedModelId;
    if (id == null) return null;
    LocalModelDescriptor? model;
    for (final candidate in LocalModelDownloader.models) {
      if (candidate.id == id) {
        model = candidate;
        break;
      }
    }
    if (model == null) return null;
    final file = await LocalModelDownloader.modelFile(model);
    if (!await file.exists()) return null;
    return file;
  }

  Future<void> load() async {
    await AiModelManager.instance.initialize();
    final file = await _resolveInstalledModel();
    if (file == null) throw const LocalLlmException('No verified local model is installed.');
    if (_loaded && _loadedModelId == AiModelManager.instance.installedModelId && _controller != null) return;
    await unload();

    final controller = LlamaController();

    // Check and clean any orphaned native model instance before attempting load
    try {
      if (await controller.isModelLoaded()) {
        await controller.dispose();
      }
    } catch (_) {}

    final configuredContext = AiModelManager.instance.config.maxContextLength;
    // For large models (4B+ weights ~2.5GB), cap context to 1024 on mobile to prevent KV cache OOM.
    // 1024 context uses ~150MB KV cache vs ~300MB for 2048, which keeps total app RSS safely below Android LMK thresholds.
    final fileBytes = await file.length();
    final isLargeModel = fileBytes > 1500 * 1024 * 1024;
    final targetContext = isLargeModel
        ? min(configuredContext > 0 ? configuredContext : 1024, 1024)
        : (configuredContext > 0 ? configuredContext : 1024);

    // Use 2 threads on mobile to run on primary performance cores without memory bus saturation or thread thrashing
    const threads = 2;

    int loadedCtx = targetContext;
    try {
      await controller.loadModel(
        modelPath: file.path,
        threads: threads,
        contextSize: targetContext,
        gpuLayers: 0,
      );
    } catch (e) {
      if (targetContext > 512) {
        await controller.loadModel(
          modelPath: file.path,
          threads: threads,
          contextSize: 512,
          gpuLayers: 0,
        );
        loadedCtx = 512;
      } else {
        rethrow;
      }
    }

    _controller = controller;
    _activeContextSize = loadedCtx;
    _loaded = true;
    _loadedModelId = AiModelManager.instance.installedModelId;
  }

  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int? maxTokens,
    double? temperature,
  }) async {
    await load();
    if (_controller == null) {
      throw const LocalLlmException('Local LLM controller is not loaded.');
    }

    // Always reset KV cache position to avoid accumulating past context overflow
    try {
      await _controller!.clearContext();
    } catch (_) {}

    // Strict prompt budgeting:
    // CRITICAL: In llama.cpp / jni_wrapper.cpp, if prompt tokens exceed contextSize,
    // (g_n_past + tokens.size() > n_ctx) causes g_n_past to become negative (e.g. 0 - n_discard),
    // leading to negative batch.pos, which triggers GGML_ASSERT in llama-kv-cache and crashes
    // the process via SIGABRT with zero Dart stack trace!
    // To prevent this completely, we guarantee prompt token count < maxPromptTokens.
    final contextLimit = _activeContextSize;
    // Cap generation tokens to 256 for mobile inference stability and fast responses
    final genTokens = (maxTokens ?? 256).clamp(64, 256);

    // Leave at least genTokens + 128 safety margin tokens for generation and ChatML overhead
    final maxPromptTokens = (contextLimit - genTokens - 128).clamp(128, 640);

    // In worst-case tokenization (1 char = 1 token for numbers/symbols), budget characters strictly:
    // maxTotalPromptChars ensures tokens.size() will NEVER exceed maxPromptTokens
    final maxTotalPromptChars = (maxPromptTokens * 1.5).floor();

    final safeSystemPrompt = systemPrompt.length > 200
        ? systemPrompt.substring(0, 200)
        : systemPrompt;

    final maxUserChars = max(150, maxTotalPromptChars - safeSystemPrompt.length - 60);

    final safeUserPrompt = userPrompt.length > maxUserChars
        ? '${userPrompt.substring(0, maxUserChars)}\n[...truncated for model memory]'
        : userPrompt;

    final chunks = <String>[];
    await _generationSubscription?.cancel();
    _generationSubscription = null;

    final done = Completer<void>();
    try {
      _generationSubscription = _controller!.generateChat(
        messages: [
          ChatMessage(role: 'system', content: safeSystemPrompt),
          ChatMessage(role: 'user', content: safeUserPrompt),
        ],
        template: 'chatml',
        temperature: temperature ?? AiModelManager.instance.config.temperature,
        maxTokens: genTokens,
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        repeatPenalty: 1.12,
        repeatLastN: 64,
      ).listen(
        chunks.add,
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
    } catch (e) {
      throw LocalLlmException('Failed to start inference: $e');
    }

    try {
      await done.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          _controller?.stop();
          throw const LocalLlmException('Generation timed out after 120 seconds.');
        },
      );
    } catch (e) {
      await _controller?.stop();
      if (e is LocalLlmException) rethrow;
      throw LocalLlmException('Inference error: $e');
    }

    final rawOutput = chunks.join();
    final text = _cleanModelText(rawOutput);
    if (text.trim().isEmpty) {
      // If thinking tags were stripped and resulted in empty, fallback to raw output without tag markers
      final fallback = rawOutput.replaceAll('<think>', '').replaceAll('</think>', '').trim();
      if (fallback.isNotEmpty) return fallback;
      throw const LocalLlmException('The local model returned an empty response.');
    }
    return text;
  }

  Future<void> stop() async {
    try {
      await _generationSubscription?.cancel();
      _generationSubscription = null;
      await _controller?.stop();
    } catch (_) {}
  }

  Future<void> unload() async {
    await stop();
    final controller = _controller;
    _controller = null;
    _loaded = false;
    _loadedModelId = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    } else {
      try {
        final probe = LlamaController();
        if (await probe.isModelLoaded()) {
          await probe.dispose();
        }
      } catch (_) {}
    }
  }

  String _cleanModelText(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    // Strip completed think blocks
    final withoutCompleteThink = value.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '').trim();
    if (withoutCompleteThink.isNotEmpty) {
      value = withoutCompleteThink;
    }
    // If thinking block was opened but not closed, strip the think open tag
    value = value.replaceAll('<think>', '').replaceAll('</think>', '').trim();
    value = value.replaceAll('<|im_end|>', '').replaceAll('<|endoftext|>', '').replaceAll('<|im_start|>', '');
    value = value.replaceAll(RegExp(r'^```(?:json|text)?\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*```$'), '');
    return value.trim();
  }
}
