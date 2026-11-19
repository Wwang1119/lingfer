import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lingfer/features/companion/lingfer_theme.dart';
import 'package:lingfer/models/book.dart';
import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/models/vocabulary_level.dart';
import 'package:lingfer/screens/reading/reading_screen.dart';
import 'package:lingfer/services/ai_translation_service.dart';
import 'package:lingfer/widgets/book_reader_presentation.dart';

const _originalAside = '(original English aside)';
const _source =
    'The diligent astronomer kept an original note $_originalAside '
    'about the trajectory and the evidence collected during the flight. '
    '这份记录还讨论了精确计算和实验结果。';

class _PendingVocabulary {
  _PendingVocabulary(this.raw, this.level, this.mode);

  final String raw;
  final VocabularyLevel level;
  final TranslationMode mode;
  final result = Completer<String?>();

  void complete(Map<String, String> vocabulary) {
    result.complete(jsonEncode(vocabulary));
  }
}

class _ControlledTranslationService extends AiTranslationService {
  _ControlledTranslationService()
    : super(proxyUrl: 'https://unused.invalid', appSecret: '');

  final requests = <_PendingVocabulary>[];

  @override
  Future<String?> fetchVocabJson({
    required String raw,
    required VocabularyLevel level,
    required TranslationMode mode,
  }) {
    final request = _PendingVocabulary(raw, level, mode);
    requests.add(request);
    return request.result.future;
  }

  List<_PendingVocabulary> forMode(TranslationMode mode) =>
      requests.where((request) => request.mode == mode).toList();

  void finishPending() {
    for (final request in requests) {
      if (!request.result.isCompleted) request.result.complete(null);
    }
  }
}

String _displayedBookText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(PageView), matching: find.byType(Text)),
    )
    .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
    .join('\n');

Future<void> _waitFor(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  required String reason,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (await tester.runAsync(() async => await condition()) == true) return;
    // Let real file I/O finish; advancing the fake clock alone cannot do that.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail(reason);
}

Future<Directory> _openReader(
  WidgetTester tester,
  _ControlledTranslationService service,
) async {
  late Directory folder;
  await tester.runAsync(() async {
    folder = await Directory.systemTemp.createTemp('lingfer-mode-integration-');
    await File('${folder.path}/bilingual.txt').writeAsString(_source);
  });
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathChannel, (call) async => folder.path);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    service.finishPending();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (await folder.exists()) await folder.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: lingferTheme(),
      home: ReadingScreen(
        book: Book(
          title: 'Direction isolation fixture',
          author: '',
          defaultLevel: VocabularyLevel.cet4,
          source: BookSource.localFile,
          locator: '${folder.path}/bilingual.txt',
        ),
        translationService: service,
      ),
    ),
  );
  await _waitFor(
    tester,
    () =>
        find.byType(PageView).evaluate().isNotEmpty &&
        service.requests.isNotEmpty,
    reason: 'The real local book should render and request its first chunk.',
  );
  expect(service.requests.single.mode, TranslationMode.enToZh);
  expect(service.requests.single.raw, _source);
  return folder;
}

Future<void> _selectDirection(
  WidgetTester tester, {
  required TranslationMode from,
  required TranslationMode to,
}) async {
  final current = find.widgetWithText(BookReaderActionChip, from.label);
  if (current.evaluate().isEmpty) {
    await tester.tapAt(const Offset(195, 422));
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(current, findsOneWidget);
  await tester.tap(current);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final choice = find.byKey(ValueKey('book-choice-$to'));
  expect(choice.hitTestable(), findsOneWidget);
  await tester.tap(choice);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.widgetWithText(BookReaderActionChip, to.label), findsOneWidget);
  await tester.tap(find.byIcon(CupertinoIcons.xmark).first);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<bool> _hasCacheMeaning(
  Directory folder, {
  required String mode,
  required String word,
  required String meaning,
}) async {
  final cache = Directory('${folder.path}/lens_cache');
  if (!await cache.exists()) return false;
  await for (final entry in cache.list(recursive: true, followLinks: false)) {
    if (entry is! File || !entry.path.endsWith('.json')) continue;
    final wrapper = jsonDecode(await entry.readAsString());
    if (wrapper is Map &&
        wrapper['mode'] == mode &&
        wrapper['rawSource'] == _source &&
        wrapper['data'] is Map &&
        wrapper['data'][word] == meaning) {
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Direction switches render only their own cached glosses', (
    tester,
  ) async {
    final service = _ControlledTranslationService();
    final folder = await _openReader(tester, service);
    service.requests.single.complete({'diligent': '勤勉的'});
    await _waitFor(
      tester,
      () => _displayedBookText(tester).contains('勤勉的'),
      reason: 'English-to-Chinese should display the generated Chinese gloss.',
    );
    expect(_displayedBookText(tester), contains(_originalAside));

    await _selectDirection(
      tester,
      from: TranslationMode.enToZh,
      to: TranslationMode.zhToEn,
    );
    await _waitFor(
      tester,
      () => service.forMode(TranslationMode.zhToEn).length == 1,
      reason: 'The new direction should request from original prose.',
    );
    expect(_displayedBookText(tester), isNot(contains('勤勉的')));
    expect(service.forMode(TranslationMode.zhToEn).single.raw, _source);
    service.forMode(TranslationMode.zhToEn).single.complete({
      '精确计算': 'precise computation',
    });
    await _waitFor(
      tester,
      () => _displayedBookText(tester).contains('precise computation'),
      reason: 'Chinese-to-English should display its own English gloss.',
    );

    await _selectDirection(
      tester,
      from: TranslationMode.zhToEn,
      to: TranslationMode.enToZh,
    );
    await _waitFor(
      tester,
      () => _displayedBookText(tester).contains('勤勉的'),
      reason: 'Returning to English-to-Chinese should restore its own cache.',
    );
    expect(_displayedBookText(tester), isNot(contains('precise computation')));
    expect(_displayedBookText(tester), contains(_originalAside));
    expect(service.requests, hasLength(2));
    expect(
      await tester.runAsync(
        () => _hasCacheMeaning(
          folder,
          mode: 'zh_en',
          word: '精确计算',
          meaning: 'precise computation',
        ),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A late response cannot overwrite the newly selected direction', (
    tester,
  ) async {
    final service = _ControlledTranslationService();
    final folder = await _openReader(tester, service);
    final oldRequest = service.requests.single;
    await _selectDirection(
      tester,
      from: TranslationMode.enToZh,
      to: TranslationMode.zhToEn,
    );
    await _waitFor(
      tester,
      () => service.forMode(TranslationMode.zhToEn).length == 1,
      reason: 'Switching while a request is pending must start the new mode.',
    );
    service.forMode(TranslationMode.zhToEn).single.complete({
      '精确计算': 'newly verified computation',
    });
    await _waitFor(
      tester,
      () => _displayedBookText(tester).contains('newly verified computation'),
      reason: 'The new request should render before the old response returns.',
    );
    await tester.pump(const Duration(milliseconds: 100));
    final currentText = _displayedBookText(tester);
    expect(currentText, contains(_originalAside));
    oldRequest.complete({'diligent': '过时返回释义'});
    // Wait for the old response to reach persistence, rather than asserting
    // before its continuation has had a chance to affect the active reader.
    await _waitFor(
      tester,
      () => _hasCacheMeaning(
        folder,
        mode: 'en_zh',
        word: 'diligent',
        meaning: '过时返回释义',
      ),
      reason:
          'The late response should finish in its separate direction cache.',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(_displayedBookText(tester), currentText);
    expect(_displayedBookText(tester), isNot(contains('过时返回释义')));
    expect(service.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
