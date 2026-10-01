import 'package:flutter/material.dart';
import '../core/theme/editorial_tokens.dart';

class DragonPetMenu extends StatelessWidget {
  final bool hasSelection;
  final VoidCallback onAskDocument;
  final VoidCallback onExplainSelection;
  final VoidCallback onStudyMode;
  final VoidCallback onAiModels;
  final VoidCallback onSummarizePage;

  const DragonPetMenu({
    super.key,
    required this.hasSelection,
    required this.onAskDocument,
    required this.onExplainSelection,
    required this.onStudyMode,
    required this.onAiModels,
    required this.onSummarizePage,
  });

  Widget _action(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 19, color: EditorialTokens.primary),
      title: Text(title, style: EditorialTokens.titleSmall(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
      subtitle: Text(subtitle, style: EditorialTokens.metadata(color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 17, color: EditorialTokens.primary),
                  const SizedBox(width: 8),
                  Text('Study Companion', style: EditorialTokens.titleMedium(color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink)),
                ],
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              _action(context, Icons.psychology_outlined, 'Ask Document', 'Open the existing grounded document Q&A', onAskDocument),
              _action(context, Icons.auto_awesome, 'Explain Selection', hasSelection ? 'Explain the selected PDF text' : 'Select text first to use this action', onExplainSelection),
              _action(context, Icons.menu_book_outlined, 'Study Mode', 'Open the existing Study Mode', onStudyMode),
              _action(context, Icons.summarize_outlined, 'Summarize Page', 'Create a local revision summary', onSummarizePage),
              _action(context, Icons.memory_outlined, 'Local AI Models', 'Download or remove the offline model', onAiModels),
            ],
          ),
        ),
      ),
    );
  }
}
