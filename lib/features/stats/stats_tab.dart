import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/thumbnail_cache_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../models/tool_usage_stat.dart';
import '../../widgets/editorial_components.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';

class StatsTab extends ConsumerStatefulWidget {
  const StatsTab({super.key});

  @override
  ConsumerState<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<StatsTab> {
  List<PdfFile> _mostOpened = [];
  List<ToolUsageStat> _toolUsage = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;
    final opened = await db.getMostOpenedFiles(limit: 5);
    final usage = await db.getToolUsageStats();

    if (mounted) {
      setState(() {
        _mostOpened = opened;
        _toolUsage = usage;
        _isLoading = false;
      });
    }
  }

  String _formatReadingTime(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';
    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final pdfState = ref.watch(pdfListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const EditorialEyebrow(text: 'READING ACTIVITY'),
                    Text(
                      'Reading & Activity',
                      style: EditorialTokens.titleLarge(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    size: 20,
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  tooltip: 'Refresh Metrics',
                  onPressed: () {
                    ref.read(pdfListProvider.notifier).scanStorage();
                    _loadStats();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: EditorialTokens.primary,
              ),
            )
          : pdfState.when(
              data: (files) {
                final totalSize = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
                return Column(
                  children: [
                    // Sub-strip: overview
                    EditorialStatStrip(
                      primaryText: '${files.length} DOCUMENTS · ${Utils.formatBytes(totalSize)}',
                      secondaryText: 'ON-DEVICE STATS',
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryCards(files, totalSize, isDark),
                            const SizedBox(height: 12),
                            _buildReadingStatsRow(files, isDark),
                            const SizedBox(height: 24),
                            const EditorialSectionHeader(
                              number: '01',
                              label: 'Storage Distribution',
                              count: 'by file size',
                            ),
                            const SizedBox(height: 8),
                            _buildChartCard(files, isDark),
                            const SizedBox(height: 24),
                            const EditorialSectionHeader(
                              number: '02',
                              label: 'Tool Operations',
                              count: 'local execution count',
                            ),
                            const SizedBox(height: 8),
                            _buildToolUsageList(isDark),
                            const SizedBox(height: 24),
                            const EditorialSectionHeader(
                              number: '03',
                              label: 'Frequent Documents',
                              count: 'top consultations',
                            ),
                            const SizedBox(height: 8),
                            _buildMostOpenedList(isDark),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EditorialTokens.primary,
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error loading metrics: $err',
                  style: EditorialTokens.metadata(color: EditorialTokens.error),
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String hint,
    required bool isDark,
    Color? accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        borderRadius: BorderRadius.circular(EditorialTokens.r4),
        border: Border.all(
          color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
          width: EditorialTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: EditorialTokens.metadataStrong(
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                ).copyWith(fontSize: 9.5),
              ),
              if (accentColor != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: EditorialTokens.headlineSmall(
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: EditorialTokens.metadata(
              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<PdfFile> files, int totalSize, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            label: 'Total Library',
            value: '${files.length}',
            hint: 'PDF documents cataloged',
            isDark: isDark,
            accentColor: EditorialTokens.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Total Footprint',
            value: Utils.formatBytes(totalSize),
            hint: 'Local storage allocation',
            isDark: isDark,
            accentColor: EditorialTokens.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildReadingStatsRow(List<PdfFile> files, bool isDark) {
    final totalReadingSec = files.fold<int>(0, (sum, f) => sum + f.readingTime);
    final completedCount = files.where((f) => f.completed).length;

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            label: 'Reading Immersion',
            value: _formatReadingTime(totalReadingSec),
            hint: 'Active viewport duration',
            isDark: isDark,
            accentColor: EditorialTokens.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Completed Books',
            value: '$completedCount / ${files.length}',
            hint: 'Documents read to 100%',
            isDark: isDark,
            accentColor: const Color(0xFF2E6F40),
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(List<PdfFile> files, bool isDark) {
    int bSmall = 0; // <1MB
    int bMedium = 0; // 1-10MB
    int bLarge = 0; // 10-50MB
    int bHuge = 0; // 50MB+

    for (final f in files) {
      final mb = f.sizeBytes / (1024 * 1024);
      if (mb < 1) {
        bSmall++;
      } else if (mb < 10) {
        bMedium++;
      } else if (mb < 50) {
        bLarge++;
      } else {
        bHuge++;
      }
    }

    final maxVal = [bSmall, bMedium, bLarge, bHuge].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        borderRadius: BorderRadius.circular(EditorialTokens.r4),
        border: Border.all(
          color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
          width: EditorialTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DOCUMENT DISTRIBUTION BY TIER',
                style: EditorialTokens.metadataStrong(
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                ).copyWith(fontSize: 10),
              ),
              Text(
                'PEAK: $maxVal DOCUMENTS',
                style: EditorialTokens.metadata(
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxVal + 2).toDouble(),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} files',
                        EditorialTokens.metadataStrong(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final label = switch (value.toInt()) {
                          0 => '<1MB',
                          1 => '1-10MB',
                          2 => '10-50MB',
                          3 => '50MB+',
                          _ => '',
                        };
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            label,
                            style: EditorialTokens.metadata(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                      toY: bSmall.toDouble(),
                      color: EditorialTokens.tertiary,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    )
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                      toY: bMedium.toDouble(),
                      color: EditorialTokens.primary,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    )
                  ]),
                  BarChartGroupData(x: 2, barRods: [
                    BarChartRodData(
                      toY: bLarge.toDouble(),
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    )
                  ]),
                  BarChartGroupData(x: 3, barRods: [
                    BarChartRodData(
                      toY: bHuge.toDouble(),
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    )
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolUsageList(bool isDark) {
    if (_toolUsage.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Text(
          'No tool invocations recorded yet.',
          style: EditorialTokens.metadata(
            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
          ),
        ),
      );
    }
    return Column(
      children: _toolUsage.map((u) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
            borderRadius: BorderRadius.circular(EditorialTokens.r4),
            border: Border.all(
              color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
              width: EditorialTokens.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(EditorialTokens.r2),
                  border: Border.all(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Text(
                  '${u.useCount}',
                  style: EditorialTokens.metadataStrong(
                    color: EditorialTokens.primary,
                  ).copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.toolName.toUpperCase().replaceAll('_', ' '),
                      style: EditorialTokens.label(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last executed: ${Utils.formatRelativeTime(u.lastUsedAt)}',
                      style: EditorialTokens.metadata(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMostOpenedList(bool isDark) {
    if (_mostOpened.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Text(
          'No recently opened documents.',
          style: EditorialTokens.metadata(
            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
          ),
        ),
      );
    }
    return Column(
      children: _mostOpened.map((f) => _MostOpenedTile(file: f, isDark: isDark)).toList(),
    );
  }
}

class _MostOpenedTile extends StatefulWidget {
  final PdfFile file;
  final bool isDark;

  const _MostOpenedTile({
    required this.file,
    required this.isDark,
  });

  @override
  State<_MostOpenedTile> createState() => _MostOpenedTileState();
}

class _MostOpenedTileState extends State<_MostOpenedTile> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final thumbFile = await ThumbnailCacheService.getThumbnailFile(widget.file.path);
    if (mounted && thumbFile != null) {
      setState(() => _thumbPath = thumbFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final isDark = widget.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        borderRadius: BorderRadius.circular(EditorialTokens.r4),
        border: Border.all(
          color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
          width: EditorialTokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerScreen(filePath: f.path),
            ),
          );
        },
        borderRadius: BorderRadius.circular(EditorialTokens.r4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              EditorialPaperThumbnail(
                thumbnailPath: _thumbPath,
                pageNumber: f.lastOpenedPage,
                totalPages: f.pageCount,
                isCompleted: f.completed,
                width: 32,
                height: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTokens.titleSmall(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Opened ${Utils.formatRelativeTime(f.lastOpenedAt)} · ${f.pageCount} pages',
                      style: EditorialTokens.metadata(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
