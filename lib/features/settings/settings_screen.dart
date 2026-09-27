import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/permissions/permissions_service.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/thumbnail_cache_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';
import '../home/pdf_list_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: EditorialTokens.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EditorialTokens.r4)),
        content: Text(
          message,
          style: EditorialTokens.bodyMedium(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isNightReadingMode = ref.watch(isNightReadingModeProvider);
    final isEyeComfortMode = ref.watch(isEyeComfortModeProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: AppBar(
        backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: 'STUDIO PREFERENCES · PRIVACY'),
            Text(
              'Settings & Storage',
              style: EditorialTokens.titleMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
            height: EditorialTokens.hairline,
          ),
        ),
      ),
      body: Column(
        children: [
          // Sub-strip: Local runtime status
          const EditorialStatStrip(
            primaryText: 'LOCAL RUNTIME ENVIRONMENT',
            secondaryText: 'OFFLINE INDEX ACTIVE',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // 1. Appearance & Reader Mode
                const EditorialSectionHeader(
                  number: '01',
                  label: 'Appearance & Reading Bed',
                  count: 'theme & color temperature',
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          'Application Theme',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          themeMode == ThemeMode.system
                              ? 'System Default'
                              : themeMode == ThemeMode.dark
                                  ? 'Dark Studio'
                                  : 'Light Quiet Editorial',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<ThemeMode>(
                            value: themeMode,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: ThemeMode.system,
                                child: Text('System', style: EditorialTokens.bodySmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.light,
                                child: Text('Light', style: EditorialTokens.bodySmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.dark,
                                child: Text('Dark', style: EditorialTokens.bodySmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                              ),
                            ],
                            onChanged: (mode) {
                              if (mode != null) {
                                ref.read(themeModeProvider.notifier).setThemeMode(mode);
                              }
                            },
                          ),
                        ),
                      ),
                      const EditorialDivider(),
                      SwitchListTile(
                        dense: true,
                        activeColor: EditorialTokens.primary,
                        title: Text(
                          'Reader Night Studio Bed',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Inverts reader background to deep charcoal for low-light study',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        value: isNightReadingMode,
                        onChanged: (val) {
                          ref.read(isNightReadingModeProvider.notifier).toggle(val);
                          if (val) {
                            ref.read(isEyeComfortModeProvider.notifier).toggle(false);
                          }
                        },
                      ),
                      const EditorialDivider(),
                      SwitchListTile(
                        dense: true,
                        activeColor: EditorialTokens.primary,
                        title: Text(
                          'Eye Comfort (Warm Sepia Protection)',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Warm amber tint filtering harsh blue light for long reading sessions',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        value: isEyeComfortMode,
                        onChanged: (val) {
                          ref.read(isEyeComfortModeProvider.notifier).toggle(val);
                          if (val) {
                            ref.read(isNightReadingModeProvider.notifier).toggle(false);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Storage & Cache Control
                const EditorialSectionHeader(
                  number: '02',
                  label: 'Persistence & Cache Control',
                  count: 'local file system',
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.security_outlined,
                          size: 20,
                          color: EditorialTokens.primary,
                        ),
                        title: Text(
                          'Manage Storage Permissions',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Verify Android All-Files-Access or Scoped Storage permissions',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        onTap: () {
                          ref.read(permissionsProvider.notifier).openAppSettingsPage();
                        },
                      ),
                      const EditorialDivider(),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.cached,
                          size: 20,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        title: Text(
                          'Purge Thumbnail Cache',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Frees disk space by removing rendered thumbnails',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        onTap: () async {
                          await ThumbnailCacheService.clearCache();
                          if (!context.mounted) return;
                          _showNotice(context, 'Thumbnail cache purged.');
                        },
                      ),
                      const EditorialDivider(),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.cleaning_services_outlined,
                          size: 20,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        title: Text(
                          'Purge OCR Full-Text Index',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Removes cached extracted texts and formulas from database',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        onTap: () async {
                          await DatabaseHelper.instance.clearOcrIndex();
                          ref.read(pdfListProvider.notifier).loadFiles();
                          if (!context.mounted) return;
                          _showNotice(context, 'OCR text index cleared.');
                        },
                      ),
                      const EditorialDivider(),
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.refresh,
                          size: 20,
                          color: EditorialTokens.primary,
                        ),
                        title: Text(
                          'Re-scan Storage Catalog',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Forces recursive re-indexing across internal & external volumes',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        onTap: () {
                          ref.read(pdfListProvider.notifier).scanStorage();
                          _showNotice(context, 'Storage catalog re-scan initiated.');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. System & Build Architecture
                const EditorialSectionHeader(
                  number: '03',
                  label: 'System & Architecture',
                  count: 'build verification',
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.info_outline,
                          size: 20,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        title: Text(
                          'Quiet Editorial Document Studio',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Design 01 · 100% Offline Archival Processing Engine',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                      ),
                      const EditorialDivider(),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        title: Text(
                          'Open Source Licenses & Attributions',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        subtitle: Text(
                          'Source Serif 4, Inter, JetBrains Mono, Syncfusion, Google ML Kit',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        onTap: () => showLicensePage(context: context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
