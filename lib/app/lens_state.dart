import 'package:flutter/widgets.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';
import '../services/asset_books_service.dart';

class LensState extends ChangeNotifier {
  LensState({required VocabularyLevel selectedLevel})
      : _selectedLevel = selectedLevel;

  VocabularyLevel _selectedLevel;
  VocabularyLevel get selectedLevel => _selectedLevel;

  final List<Book> _bookshelf = <Book>[];
  List<Book> get bookshelf => List<Book>.unmodifiable(_bookshelf);

  void setLevel(VocabularyLevel level) {
    if (_selectedLevel == level) return;
    _selectedLevel = level;
    notifyListeners();
  }

  void addImported(Book book) {
    _bookshelf.removeWhere((b) => b.stableKey == book.stableKey);
    _bookshelf.insert(0, book);
    notifyListeners();
  }

  void updateBook(Book previous, Book next) {
    final idx = _bookshelf.indexWhere((b) =>
        b.stableKey == previous.stableKey && b.locator == previous.locator);
    if (idx == -1) return;
    _bookshelf.removeAt(idx);
    _bookshelf.insert(idx, next);
    notifyListeners();
  }

  Future<void> initializeBookshelf() async {
    final bundled = await AssetBooksService().loadBundledBooks(
      defaultLevel: _selectedLevel,
    );
    _bookshelf
      ..clear()
      ..addAll(bundled);
    notifyListeners();
  }
}

class LensScope extends InheritedNotifier<LensState> {
  const LensScope({super.key, required LensState state, required super.child})
      : super(notifier: state);

  static LensState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LensScope>();
    assert(scope != null, 'LensScope not found');
    return scope!.notifier!;
  }
}
