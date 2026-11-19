import '../models/book.dart';

/// Hides the managed-copy prefix in labels without changing identity or progress keys.
extension BookDisplayTitle on Book {
  String get displayTitle {
    final path = locator.replaceAll('\\', '/');
    if (source != BookSource.localFile ||
        !path.contains('/Lingfer/ImportedBooks/')) {
      return title;
    }
    final prefix = RegExp(r'^[a-fA-F0-9]{8}_').firstMatch(path.split('/').last);
    if (prefix == null || !title.startsWith(prefix.group(0)!)) return title;
    return title.substring(prefix.end);
  }
}
