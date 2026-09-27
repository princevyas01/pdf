enum DiffType { unchanged, modified, added, removed }

class PageDiff {
  final int pageNumber;
  final int? pageNumberA;
  final int? pageNumberB;
  final DiffType diffType;
  final List<String> addedLines;
  final List<String> removedLines;
  final bool hasVisualDiff;

  PageDiff({
    required this.pageNumber,
    this.pageNumberA,
    this.pageNumberB,
    this.diffType = DiffType.modified,
    this.addedLines = const [],
    this.removedLines = const [],
    this.hasVisualDiff = false,
  });

  bool get hasDiff => diffType != DiffType.unchanged || addedLines.isNotEmpty || removedLines.isNotEmpty || hasVisualDiff;
}

class PdfCompareResult {
  final String fileAPath;
  final String fileBPath;
  final int fileAPages;
  final int fileBPages;
  final List<PageDiff> pageDiffs;
  final String summary;

  PdfCompareResult({
    required this.fileAPath,
    required this.fileBPath,
    required this.fileAPages,
    required this.fileBPages,
    required this.pageDiffs,
    required this.summary,
  });
}
