import 'dart:async';
import 'dart:io';
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
    if (_loaded && _loadedModelId == AiModelManager.instance.installedModelId) return;
    await unload();
    final controller = LlamaController();
    final gpu = await controller.detectGpu();
    await controller.loadModel(
      modelPath: file.path,
      threads: 4,
      contextSize: AiModelManager.instance.config.maxContextLength,
      gpuLayers: gpu.recommendedGpuLayers,
    );
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
    final chunks = <String>[];

    await _generationSubscription?.cancel();
    final done = Completer<void>();
    _generationSubscription = _controller!.generateChat(
      messages: [
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: userPrompt),
      ],
      template: 'chatml',
      temperature: temperature ?? AiModelManager.instance.config.temperature,
      maxTokens: maxTokens ?? 512,
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
    );
    await done.future;
    final text = _cleanModelText(chunks.join());
    if (text.trim().isEmpty) {
      throw const LocalLlmException('The local model returned an empty response.');
    }
    return text;
  }

  Future<void> stop() async {
    await _controller?.stop();
    await _generationSubscription?.cancel();
    _generationSubscription = null;
  }

  Future<void> unload() async {
    await stop();
    final controller = _controller;
    _controller = null;
    _loaded = false;
    _loadedModelId = null;
    await controller?.dispose();
  }

  String _cleanModelText(String text) {
    var value = text.replaceAll('\r\n', '\n').trim();
    value = value.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '').trim();
    value = value.replaceAll(RegExp(r'^```(?:json|text)?\s*', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*```$'), '');
    return value.trim();
  }
}
