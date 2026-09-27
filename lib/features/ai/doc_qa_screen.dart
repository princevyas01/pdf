import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/ai/on_device_ai_service.dart';
import '../../core/storage/ocr_cache_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../viewer/pdf_viewer_screen.dart';

class QAMessage {
  final String text;
  final bool isUser;
  final List<int> sourcePages;

  QAMessage({
    required this.text,
    required this.isUser,
    this.sourcePages = const [],
  });
}

class DocQaScreen extends ConsumerStatefulWidget {
  final PdfFile pdfFile;

  const DocQaScreen({super.key, required this.pdfFile});

  @override
  ConsumerState<DocQaScreen> createState() => _DocQaScreenState();
}

class _DocQaScreenState extends ConsumerState<DocQaScreen> {
  final TextEditingController _questionController = TextEditingController();
  final List<QAMessage> _messages = [];
  Map<int, String> _pageTextMap = {};
  bool _isLoadingContext = true;
  bool _isThinking = false;

  @override
  void initState() {
    super.initState();
    _loadDocumentText();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentText() async {
    final cachedOcr = await OcrCacheService.getCachedFileOcr(widget.pdfFile.path);
    _pageTextMap = Map.from(cachedOcr);

    if (_pageTextMap.isEmpty) {
      try {
        final fileBytes = await File(widget.pdfFile.path).readAsBytes();
        if (!mounted) return;
        final document = sf.PdfDocument(inputBytes: fileBytes);
        final extractor = sf.PdfTextExtractor(document);

        for (int i = 0; i < document.pages.count; i++) {
          final text = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
          if (text.isNotEmpty) {
            _pageTextMap[i + 1] = text;
          }
        }
        document.dispose();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoadingContext = false;
        _messages.add(
          QAMessage(
            text: 'Greetings. I am your local grounded reading assistant for "${widget.pdfFile.name}". All queries and contextual citations are computed 100% on-device.',
            isUser: false,
          ),
        );
      });
    }
  }

  Future<void> _sendQuestion() async {
    final q = _questionController.text.trim();
    if (q.isEmpty || _isThinking) return;

    _questionController.clear();
    setState(() {
      _messages.add(QAMessage(text: q, isUser: true));
      _isThinking = true;
    });

    final answerResult = await OnDeviceAIService.instance.answerQuestion(
      filePath: widget.pdfFile.path,
      question: q,
      pageTextMap: _pageTextMap,
    );

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(
          QAMessage(
            text: answerResult.answer,
            isUser: false,
            sourcePages: answerResult.sourcePages,
          ),
        );
      });
    }
  }

  void _navigateToPage(int pageNumber) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: widget.pdfFile.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: 'GROUNDED SYNTHESIS · 100% OFFLINE'),
            Text(
              'Ask Document',
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
      body: _isLoadingContext
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EditorialTokens.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'INDEXING DOCUMENT CONTEXT...',
                    style: EditorialTokens.eyebrow(color: EditorialTokens.primary),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Document reference strip
                EditorialStatStrip(
                  primaryText: 'ACTIVE DOCUMENT · ${widget.pdfFile.name.toUpperCase()}',
                  secondaryText: 'ON-DEVICE NEURAL CACHE',
                ),

                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];

                      if (msg.isUser) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          alignment: Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.8,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.primary,
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              border: Border.all(
                                color: isDark ? EditorialTokens.darkBorder : EditorialTokens.primary,
                                width: EditorialTokens.hairline,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'READER INQUIRY',
                                  style: EditorialTokens.eyebrow(
                                    color: isDark ? EditorialTokens.primary : Colors.white70,
                                  ).copyWith(fontSize: 9),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  msg.text,
                                  style: EditorialTokens.body(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Assistant message on physical paper
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.88,
                          ),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? EditorialTokens.darkSurface : EditorialTokens.paper,
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
                                children: [
                                  const EditorialEyebrow(
                                    text: 'LOCAL SYNTHESIS',
                                    color: EditorialTokens.primary,
                                  ),
                                  const Spacer(),
                                  Text(
                                    '100% PRIVATE',
                                    style: EditorialTokens.metadata(
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ).copyWith(fontSize: 9),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                msg.text,
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  fontSize: 14,
                                  height: 1.5,
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ),
                              ),
                              if (msg.sourcePages.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const EditorialDivider(),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'CITATIONS:',
                                      style: EditorialTokens.metadataStrong(
                                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                      ).copyWith(fontSize: 9),
                                    ),
                                    ...msg.sourcePages.map(
                                      (page) => InkWell(
                                        onTap: () => _navigateToPage(page),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: EditorialTokens.primary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                            border: Border.all(
                                              color: EditorialTokens.primary.withOpacity(0.3),
                                              width: EditorialTokens.hairline,
                                            ),
                                          ),
                                          child: Text(
                                            'PAGE $page',
                                            style: EditorialTokens.metadataStrong(
                                              color: EditorialTokens.primary,
                                            ).copyWith(fontSize: 9.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                if (_isThinking)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: EditorialTokens.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'ANALYZING DOCUMENT TEXT...',
                          style: EditorialTokens.eyebrow(color: EditorialTokens.primary),
                        ),
                      ],
                    ),
                  ),

                // Docked query input bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          style: EditorialTokens.body(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask a question about this document...',
                            hintStyle: EditorialTokens.bodySmall(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: (_) => _sendQuestion(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_upward,
                          size: 20,
                          color: EditorialTokens.primary,
                        ),
                        onPressed: _sendQuestion,
                        tooltip: 'Send question',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
