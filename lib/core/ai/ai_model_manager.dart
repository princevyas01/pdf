import '../../models/ai_model_config.dart';
import '../storage/database_helper.dart';

class AiModelManager {
  static final AiModelManager instance = AiModelManager._init();

  AiModelConfig _config = AiModelConfig(
    isInstalled: true,
    isEnabled: true,
    modelName: 'Offline-Local-NLP-Engine-v1',
    sizeMb: 12.5,
    statusMessage: 'Ready (On-Device Local Engine Active)',
  );

  AiModelManager._init();

  AiModelConfig get config => _config;

  void toggleEnabled(bool enabled) {
    _config = _config.copyWith(
      isEnabled: enabled,
      statusMessage: enabled ? 'Ready (On-Device Local Engine Active)' : 'Disabled by User',
    );
  }

  void updateSettings({int? maxContext, double? temp, bool? autoUnload}) {
    _config = _config.copyWith(
      maxContextLength: maxContext ?? _config.maxContextLength,
      temperature: temp ?? _config.temperature,
      autoUnload: autoUnload ?? _config.autoUnload,
    );
  }

  Future<String?> getCachedResponse(String cacheKey) async {
    return await DatabaseHelper.instance.getCachedAiResponse(cacheKey);
  }

  Future<void> cacheResponse(String cacheKey, String response, String filePath) async {
    await DatabaseHelper.instance.cacheAiResponse(cacheKey, response, filePath);
  }
}
