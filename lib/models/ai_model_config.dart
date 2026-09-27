class AiModelConfig {
  final bool isInstalled;
  final bool isEnabled;
  final String modelName;
  final double sizeMb;
  final String statusMessage;
  final int maxContextLength;
  final double temperature;
  final bool autoUnload;

  AiModelConfig({
    required this.isInstalled,
    required this.isEnabled,
    required this.modelName,
    required this.sizeMb,
    required this.statusMessage,
    this.maxContextLength = 2048,
    this.temperature = 0.7,
    this.autoUnload = true,
  });

  AiModelConfig copyWith({
    bool? isInstalled,
    bool? isEnabled,
    String? modelName,
    double? sizeMb,
    String? statusMessage,
    int? maxContextLength,
    double? temperature,
    bool? autoUnload,
  }) {
    return AiModelConfig(
      isInstalled: isInstalled ?? this.isInstalled,
      isEnabled: isEnabled ?? this.isEnabled,
      modelName: modelName ?? this.modelName,
      sizeMb: sizeMb ?? this.sizeMb,
      statusMessage: statusMessage ?? this.statusMessage,
      maxContextLength: maxContextLength ?? this.maxContextLength,
      temperature: temperature ?? this.temperature,
      autoUnload: autoUnload ?? this.autoUnload,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'is_installed': isInstalled ? 1 : 0,
      'is_enabled': isEnabled ? 1 : 0,
      'model_name': modelName,
      'size_mb': sizeMb,
      'status_message': statusMessage,
      'max_context_length': maxContextLength,
      'temperature': temperature,
      'auto_unload': autoUnload ? 1 : 0,
    };
  }

  factory AiModelConfig.fromMap(Map<String, dynamic> map) {
    return AiModelConfig(
      isInstalled: map['is_installed'] == 1 || map['is_installed'] == true,
      isEnabled: map['is_enabled'] == 1 || map['is_enabled'] == true,
      modelName: map['model_name'] as String? ?? '',
      sizeMb: (map['size_mb'] as num?)?.toDouble() ?? 0.0,
      statusMessage: map['status_message'] as String? ?? '',
      maxContextLength: (map['max_context_length'] as num?)?.toInt() ?? 2048,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.7,
      autoUnload: map['auto_unload'] == 1 || map['auto_unload'] == true,
    );
  }
}
