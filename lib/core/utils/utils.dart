import 'package:intl/intl.dart';

class Utils {
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";

    const suffixes = ["B", "KB", "MB", "GB", "TB"];

    int i = 0;
    double value = bytes.toDouble();

    while (value >= 1024 && i < suffixes.length - 1) {
      value /= 1024;
      i++;
    }

    return "${value.toStringAsFixed(decimals)} ${suffixes[i]}";
  }

  static String formatDate(int millisecondsSinceEpoch) {
    if (millisecondsSinceEpoch <= 0) return "";
    final date = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return DateFormat('MMM dd, yyyy  hh:mm a').format(date);
  }

  static String formatRelativeTime(int? millisecondsSinceEpoch) {
    if (millisecondsSinceEpoch == null || millisecondsSinceEpoch <= 0) {
      return "Never";
    }
    final date = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    return DateFormat('MMM dd, yyyy').format(date);
  }

  /// Parses page ranges like "1-5, 8, 11-20" into a set of 1-based page numbers.
  static Set<int> parsePageRanges(String input, int maxPages) {
    final Set<int> result = {};
    if (input.trim().isEmpty || maxPages <= 0) return result;

    final parts = input.split(',');
    for (var part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      if (part.contains('-')) {
        final range = part.split('-');
        if (range.length == 2) {
          final start = int.tryParse(range[0].trim());
          final end = int.tryParse(range[1].trim());
          if (start != null &&
              end != null &&
              start > 0 &&
              start <= maxPages &&
              end >= start) {
            final actualEnd = end > maxPages ? maxPages : end;
            for (int i = start; i <= actualEnd; i++) {
              result.add(i);
            }
          }
        }
      } else {
        final page = int.tryParse(part);
        if (page != null && page > 0 && page <= maxPages) {
          result.add(page);
        }
      }
    }
    return result;
  }
}
