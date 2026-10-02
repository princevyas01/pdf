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

  bool get isLoaded => _loaded;

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
    final contextSize = AiModelManager.instance.config.maxContextLength;
    final threads = Platform.numberOfProcessors > 0
        ? min(Platform.numberOfProcessors, 4)
        : 4;

    try {
      await controller.loadModel(
        modelPath: file.path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: 0,
      );
    } catch (e) {
      if (contextSize > 1024) {
        await controller.loadModel(
          modelPath: file.path,
          threads: threads,
          contextSize: 1024,
          gpuLayers: 0,
        );
      } else {
        rethrow;
      }
    }

    _controller = controller;
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

    // Safe context budget calculation:
    // Ensure total prompt tokens + max generation tokens stays strictly below contextSize
    final contextLimit = AiModelManager.instance.config.maxContextLength;
    final genTokens = (maxTokens ?? 512).clamp(64, 512);
    // Allow at most contextLimit - genTokens - 64 tokens for the input prompt
    final maxPromptTokens = (contextLimit - genTokens - 64).clamp(256, contextLimit - 128);
    // At ~3 chars/token (conservative for technical text/symbols/numbers), budget chars:
    final maxPromptChars = maxPromptTokens * 3;

    final safeSystemPrompt = systemPrompt.length > 400
        ? systemPrompt.substring(0, 400)
        : systemPrompt;
    final maxUserChars = max(200, maxPromptChars - safeSystemPrompt.length - 80);

    final safeUserPrompt = userPrompt.length > maxUserChars
        ? '${userPrompt.substring(0, maxUserChars)}\n[...content truncated for model capacity]'
        : userPrompt;

    final chunks = <String>[];
    await _generationSubscription?.cancel();
    _generationSubscription = null;

    final done = Completer<void>();
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

    final text = _cleanModelText(chunks.join());
    if (text.trim().isEmpty) {
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
    }
  }

  String _cleanModelText(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    value = value.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '').trim();
    value = value.replaceAll(RegExp(r'<think>[\s\S]*$', multiLine: true), '').trim();
    value = value.replaceAll('<|im_end|>', '').replaceAll('<|endoftext|>', '').replaceAll('<|im_start|>', '');
    value = value.replaceAll(RegExp(r'^```(?:json|text)?\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*```$'), '');
    return value.trim();
  }
}
