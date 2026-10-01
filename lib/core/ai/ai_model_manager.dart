import 'package:shared_preferences/shared_preferences.dart';
import '../../models/ai_model_config.dart';

class AiModelManager {
  static final AiModelManager instance = AiModelManager._init();
  static const _modelIdKey = 'local_ai_model_id';
  static const _enabledKey = 'local_ai_enabled';
  static const _autoUnloadKey = 'local_ai_auto_unload';
  static const _contextKey = 'local_ai_context';
  static const _temperatureKey = 'local_ai_temperature';

  AiModelConfig _config = AiModelConfig(
    isInstalled: false,
    isEnabled: true,
    modelName: '',
    sizeMb: 0,
    statusMessage: 'No local model installed.',
  );
  String? _installedModelId;
  bool _initialized = false;

  AiModelManager._init();

  AiModelConfig get config => _config;
  String? get installedModelId => _installedModelId;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _installedModelId = prefs.getString(_modelIdKey);
    final enabled = prefs.getBool(_enabledKey) ?? true;
    final autoUnload = prefs.getBool(_autoUnloadKey) ?? true;
    final context = prefs.getInt(_contextKey) ?? 2048;
    final temperature = prefs.getDouble(_temperatureKey) ?? 0.35;

    _config = _config.copyWith(
      isInstalled: _installedModelId != null,
      isEnabled: enabled,
      modelName: _installedModelId ?? '',
      statusMessage: _installedModelId != null
          ? 'Local model selected. Verifying file before inference.'
          : 'No local model installed.',
      maxContextLength: context,
      temperature: temperature,
      autoUnload: autoUnload,
    );
    _initialized = true;
  }

  Future<void> setInstalledModel({
    required String modelId,
    required String modelName,
    required double sizeMb,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelIdKey, modelId);
    _installedModelId = modelId;
    _config = _config.copyWith(
      isInstalled: true,
      modelName: modelName,
      sizeMb: sizeMb,
      statusMessage: 'Installed local model ready.',
    );
  }

  Future<void> clearInstalledModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelIdKey);
    _installedModelId = null;
    _config = _config.copyWith(
      isInstalled: false,
      modelName: '',
      sizeMb: 0,
      statusMessage: 'No local model installed.',
    );
  }

  Future<void> toggleEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    _config = _config.copyWith(
      isEnabled: enabled,
      statusMessage: !enabled
          ? 'Local AI disabled by user.'
          : (_config.isInstalled
              ? 'Installed local model ready.'
              : 'No local model installed.'),
    );
  }

  Future<void> updateSettings({int? maxContext, double? temp, bool? autoUnload}) async {
    final prefs = await SharedPreferences.getInstance();
    if (maxContext != null) await prefs.setInt(_contextKey, maxContext);
    if (temp != null) await prefs.setDouble(_temperatureKey, temp);
    if (autoUnload != null) await prefs.setBool(_autoUnloadKey, autoUnload);
    _config = _config.copyWith(
      maxContextLength: maxContext ?? _config.maxContextLength,
      temperature: temp ?? _config.temperature,
      autoUnload: autoUnload ?? _config.autoUnload,
    );
  }
}
