import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/ai/ai_model_manager.dart';
import '../../core/ai/local_model_downloader.dart';
import '../../core/ai/local_llm_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';

class LocalAiModelsScreen extends StatefulWidget {
  const LocalAiModelsScreen({super.key});

  @override
  State<LocalAiModelsScreen> createState() => _LocalAiModelsScreenState();
}

class _LocalAiModelsScreenState extends State<LocalAiModelsScreen> {
  String? _downloadingId;
  bool _cancelRequested = false;
  bool _initializing = true;
  int _received = 0;
  int _total = 0;
  String? _statusText;
  String? _error;
  String? _failedModelId;
  Map<String, bool> _installedMap = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _refreshInstalledState() async {
    final map = <String, bool>{};
    for (final model in LocalModelDownloader.models) {
      map[model.id] = await LocalModelDownloader.isInstalled(model);
    }
    if (mounted) {
      setState(() => _installedMap = map);
    }
  }

  Future<void> _initialize() async {
    await AiModelManager.instance.initialize();
    await _refreshInstalledState();
    if (!mounted) return;
    setState(() => _initializing = false);
  }

  Future<void> _download(LocalModelDescriptor model) async {
    if (_downloadingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Operation in progress: ${_statusText ?? "Working..."}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _downloadingId = model.id;
      _cancelRequested = false;
      _received = 0;
      _total = model.expectedSizeBytes ?? 0;
      _statusText = 'Connecting...';
      _error = null;
      _failedModelId = null;
    });
    try {
      await LocalModelDownloader.download(
        model,
        isCancelled: () => _cancelRequested,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _statusText = status);
        },
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : _total;
            if (_statusText == null ||
                _statusText!.startsWith('Connecting') ||
                _statusText!.startsWith('Downloading') ||
                _statusText!.startsWith('Resuming')) {
              _statusText =
                  'Downloading: ${(_received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_total / (1024 * 1024)).toStringAsFixed(1)} MB';
            }
          });
        },
      );
      if (!mounted) return;
      setState(() => _statusText = 'Finalizing installation...');
      await LocalLlmService.instance.unload();
      await AiModelManager.instance.setInstalledModel(
        modelId: model.id,
        modelName: model.name,
        sizeMb: model.sizeMb ?? 0,
      );
      await _refreshInstalledState();
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _statusText = null;
        _cancelRequested = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} installed and verified.')),
      );
    } catch (e) {
      await _refreshInstalledState();
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _statusText = null;
        _cancelRequested = false;
        _error = e.toString();
        _failedModelId = model.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model setup error: $e')),
      );
    }
  }

  void _cancelDownload() {
    if (_downloadingId == null) return;
    setState(() => _cancelRequested = true);
  }

  Future<void> _delete(LocalModelDescriptor model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove local model?'),
        content: Text('This removes ${model.name} from app storage. PDF files, notes and study data are unaffected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await LocalLlmService.instance.unload();
    await LocalModelDownloader.delete(model);
    if (AiModelManager.instance.installedModelId == model.id) {
      await AiModelManager.instance.clearInstalledModel();
    }
    await _refreshInstalledState();
  }

  Future<void> _activateModel(LocalModelDescriptor model) async {
    await LocalLlmService.instance.unload();
    await AiModelManager.instance.setInstalledModel(
      modelId: model.id,
      modelName: model.name,
      sizeMb: model.sizeMb ?? 0,
    );
    await _refreshInstalledState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final manager = AiModelManager.instance;
    final busy = _downloadingId != null;

    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: AppBar(
        backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: 'LOCAL INTELLIGENCE · OFFLINE'),
            Text('Local AI Models', style: EditorialTokens.titleMedium(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
          ],
        ),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const EditorialSectionHeader(number: '01', label: 'On-Device Model Storage', count: 'GGUF models'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border, width: EditorialTokens.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(manager.config.isInstalled ? manager.config.modelName : 'No model installed', style: EditorialTokens.titleSmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                      const SizedBox(height: 4),
                      Text(manager.config.statusMessage, style: EditorialTokens.metadata(color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary)),
                      const SizedBox(height: 8),
                      Text('Models are downloaded once, verified by SHA-256, and kept inside the app\'s private support directory.', style: EditorialTokens.bodySmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: EditorialTokens.metadata(color: EditorialTokens.secondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const EditorialSectionHeader(number: '02', label: 'Available Models', count: 'download on demand'),
                const SizedBox(height: 8),
                ...LocalModelDownloader.models.map((model) {
                  final downloading = _downloadingId == model.id;
                  final installed = _installedMap[model.id] == true;
                  final active = installed && manager.installedModelId == model.id && manager.config.isInstalled;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      border: Border.all(color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border, width: EditorialTokens.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(model.name, style: EditorialTokens.titleSmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink))),
                          Text(model.displaySize, style: EditorialTokens.metadataStrong(color: EditorialTokens.primary)),
                        ]),
                        const SizedBox(height: 4),
                        Text(model.description, style: EditorialTokens.metadata(color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary)),
                        const SizedBox(height: 4),
                        Text('License: ${model.license}', style: EditorialTokens.metadata(color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary)),
                        const SizedBox(height: 10),
                        if (downloading) ...[
                          LinearProgressIndicator(
                            value: (_statusText != null &&
                                    (_statusText!.contains('Verifying') ||
                                     _statusText!.contains('Installing') ||
                                     _statusText!.contains('Finalizing')))
                                ? null
                                : (_total > 0 ? (_received / _total).clamp(0.0, 1.0) : null),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _statusText ??
                                      (_total > 0
                                          ? '${(_received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_total / (1024 * 1024)).toStringAsFixed(1)} MB'
                                          : '${(_received / (1024 * 1024)).toStringAsFixed(1)} MB'),
                                  style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                                ),
                              ),
                              if (_statusText == null ||
                                  (!_statusText!.contains('Verifying') &&
                                   !_statusText!.contains('Installing') &&
                                   !_statusText!.contains('Finalizing')))
                                TextButton(
                                  onPressed: _cancelRequested ? null : _cancelDownload,
                                  child: Text(_cancelRequested ? 'Stopping...' : 'Cancel'),
                                ),
                            ],
                          ),
                        ] else ...[
                          if (_error != null && _failedModelId == model.id) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: EditorialTokens.secondary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                border: Border.all(
                                  color: EditorialTokens.secondary.withOpacity(0.3),
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 16, color: EditorialTokens.secondary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!, style: EditorialTokens.metadata(color: EditorialTokens.secondary)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (installed) ...[
                            Row(
                              children: [
                                const Icon(Icons.verified_outlined, size: 18, color: EditorialTokens.primary),
                                const SizedBox(width: 6),
                                Text(
                                  active ? 'Active Model' : 'Installed & Verified',
                                  style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                                ),
                                const Spacer(),
                                if (!active)
                                  TextButton(
                                    onPressed: busy ? null : () => _activateModel(model),
                                    child: const Text('Select'),
                                  ),
                                TextButton(
                                  onPressed: busy ? null : () => _delete(model),
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          ] else
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: () => _download(model),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Download Model'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 18),
                const EditorialSectionHeader(number: '03', label: 'Runtime Controls', count: 'memory safe defaults'),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable Local AI'),
                  subtitle: const Text('Use the downloaded GGUF model for document and study tasks.'),
                  value: manager.config.isEnabled,
                  onChanged: (v) async { await manager.toggleEnabled(v); if (mounted) setState(() {}); },
                ),
                ListTile(
                  title: const Text('Context Length'),
                  subtitle: Text('${manager.config.maxContextLength} tokens'),
                  trailing: DropdownButton<int>(
                    value: manager.config.maxContextLength,
                    items: const [
                      DropdownMenuItem(value: 1024, child: Text('1024')),
                      DropdownMenuItem(value: 2048, child: Text('2048')),
                    ],
                    onChanged: (v) async { if (v == null) return; await manager.updateSettings(maxContext: v); if (mounted) setState(() {}); },
                  ),
                ),
                SwitchListTile(
                  title: const Text('Unload Model Automatically'),
                  subtitle: const Text('Release native model memory when the AI workflow finishes.'),
                  value: manager.config.autoUnload,
                  onChanged: (v) async { await manager.updateSettings(autoUnload: v); if (mounted) setState(() {}); },
                ),
                const SizedBox(height: 18),
                Text(
                  'Privacy: inference stays on-device after the model has been downloaded. Internet is required only for the explicit download action.',
                  style: EditorialTokens.metadata(color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                ),
              ],
            ),
    );
  }
}
