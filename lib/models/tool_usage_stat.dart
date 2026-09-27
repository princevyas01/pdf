class ToolUsageStat {
  final String toolName;
  final int useCount;
  final int? lastUsedAt;

  ToolUsageStat({
    required this.toolName,
    required this.useCount,
    this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tool_name': toolName,
      'use_count': useCount,
      'last_used_at': lastUsedAt,
    };
  }

  factory ToolUsageStat.fromMap(Map<String, dynamic> map) {
    return ToolUsageStat(
      toolName: map['tool_name'] as String? ?? '',
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      lastUsedAt: (map['last_used_at'] as num?)?.toInt(),
    );
  }
}
