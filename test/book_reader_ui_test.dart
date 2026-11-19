import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingfer/features/companion/lingfer_theme.dart';
import 'package:lingfer/models/book.dart';
import 'package:lingfer/models/vocabulary_level.dart';
import 'package:lingfer/screens/reading/reading_screen.dart';
import 'package:lingfer/widgets/book_reader_presentation.dart';
import 'package:lingfer/widgets/reading_text.dart';

const _captureKey = ValueKey('reader-ui-capture');

Future<void> pumpReaderUi(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(320, 568),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: lingferTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: _captureKey,
          child: ColoredBox(color: LingferColors.background, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('LINGFER_CAPTURE_READER_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/book-reader-ui-renderings');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('LINGFER_CAPTURE_READER_UI')) return;
    final display = FontLoader('LingferDisplay')
      ..addFont(rootBundle.load('assets/fonts/lingfer-display-semibold.ttf'));
    await display.load();
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await icons.load();
    // Local visual review only: use an installed CJK font instead of Ahem.
    // The system font is never copied into the app or repository.
    final localFont = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (await localFont.exists()) {
      final bytes = ByteData.sublistView(await localFont.readAsBytes());
      for (final family in [
        'Roboto',
        '.SF UI Text',
        '.SF Pro Text',
        'PingFang SC',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Old cached level colours do not change annotation ink or source text',
    (tester) async {
      const source = '保留原文(original context)，继续阅读(continue reading)。';
      await pumpReaderUi(
        tester,
        const Scaffold(
          body: Column(
            children: [
              ReadingText(
                chunkText: source,
                accentColor: Color(0xFF4CAF50),
                fontSize: 18,
                baseColor: LingferColors.ink,
              ),
              ReadingText(
                chunkText: source,
                accentColor: Color(0xFF9C27B0),
                fontSize: 18,
                baseColor: LingferColors.ink,
              ),
            ],
          ),
        ),
      );
      final renders = tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => text.textSpan != null)
          .toList();
      expect(renders.length, 2);
      for (final text in renders) {
        expect(text.textSpan!.toPlainText(), source);
        final span = text.textSpan! as TextSpan;
        final annotation = span.children!.whereType<TextSpan>().firstWhere(
          (span) => span.text == 'original context',
        );
        expect(annotation.style!.color, LingferColors.accent);
        expect(annotation.style!.fontWeight, FontWeight.w500);
        expect(span.style!.height, 1.6);
        expect(text.strutStyle!.height, 1.6);
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'quiet-inline-annotations');
    },
  );

  testWidgets('All seven ranges stay reachable on a narrow large-text screen', (
    tester,
  ) async {
    VocabularyLevel? picked;
    var closed = false;
    Widget sheet() => BookReaderChoices<VocabularyLevel>(
      title: '学习范围',
      subtitle: '按所选范围补充阅读注释，已完成的段落保留缓存。',
      selected: VocabularyLevel.cet4,
      choices: [
        for (final level in VocabularyLevel.values)
          BookReaderChoice(value: level, label: level.label),
      ],
      onSelected: (value) => picked = value,
      onClose: () => closed = true,
    );
    if (const bool.fromEnvironment('LINGFER_CAPTURE_READER_UI')) {
      await pumpReaderUi(tester, sheet(), size: const Size(390, 844));
      await capture(tester, 'ranges-compact-normal-type');
    }
    await pumpReaderUi(tester, sheet(), scale: 2);
    expect(tester.takeException(), isNull);
    await capture(tester, 'ranges-large-type');
    final last = find.byKey(
      const ValueKey('book-choice-VocabularyLevel.toefl'),
    );
    await tester.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(last);
    expect(picked, VocabularyLevel.toefl);
    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Choices wrap long content and scroll in landscape', (
    tester,
  ) async {
    await pumpReaderUi(
      tester,
      BookReaderChoices<int>(
        title: '排版方向',
        selected: 0,
        choices: const [
          BookReaderChoice(value: 0, label: '横向翻页', detail: '保留完整正文与当前阅读进度。'),
          BookReaderChoice(
            value: 1,
            label: '竖向滑动',
            detail: '长内容按原有阅读顺序向下展开，可随时回到已经读过的段落。',
          ),
        ],
        isDark: true,
        onSelected: (_) {},
        onClose: () {},
      ),
      size: const Size(640, 320),
      scale: 1.8,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -130));
    await tester.pump();
    expect(find.text('竖向滑动'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'layout-landscape-large-type');
  });

  testWidgets(
    'Read failures keep retry and return-to-import actions accessible',
    (tester) async {
      var retried = false;
      var returned = false;
      await pumpReaderUi(
        tester,
        BookReadFailureView(
          title: '原来保存在书架里的资料',
          message: '原文件暂时无法读取，请返回后重新导入这份资料。',
          onBack: () => returned = true,
          onRetry: () => retried = true,
        ),
        size: const Size(320, 480),
        scale: 2,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.scrollUntilVisible(
        find.text('重新读取'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('重新读取'));
      expect(retried, isTrue);
      await tester.scrollUntilVisible(
        find.text('返回重新导入'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('返回重新导入'));
      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
      await capture(tester, 'unavailable-book-large-type');
    },
  );

  testWidgets(
    'The shared PDF and scan range summary opens a scrollable large-text list',
    (tester) async {
      VocabularyLevel? selected;
      await pumpReaderUi(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: BookReaderRangeSelector(
              selected: VocabularyLevel.cet4,
              onSelected: (value) => selected = value,
            ),
          ),
        ),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('book-reading-range-summary')))
            .height,
        lessThan(180),
      );
      await capture(tester, 'shared-range-summary-large-type');
      await tester.tap(
        find.byKey(const ValueKey('book-reading-range-summary')),
      );
      await tester.pumpAndSettle();
      final last = find.byKey(
        const ValueKey('book-choice-VocabularyLevel.toefl'),
      );
      await tester.scrollUntilVisible(
        last,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(selected, VocabularyLevel.toefl);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An English book starts with English-to-Chinese reading direction',
    (tester) async {
      late Directory folder;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp(
          'lingfer-english-reader-',
        );
        await File('${folder.path}/english.txt').writeAsString(
          'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do. Once or twice she had peeped into the book her sister was reading.',
        );
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => folder.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        if (await folder.exists()) await folder.delete(recursive: true);
      });
      await pumpReaderUi(
        tester,
        ReadingScreen(
          book: Book(
            title: 'English book',
            author: '',
            defaultLevel: VocabularyLevel.cet4,
            source: BookSource.localFile,
            locator: '${folder.path}/english.txt',
          ),
        ),
      );
      for (var i = 0; i < 20 && find.byType(PageView).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(PageView), findsOneWidget);
      await tester.tapAt(const Offset(160, 284));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('英译中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    },
  );

  testWidgets(
    'An empty local document finishes with an error instead of an endless spinner',
    (tester) async {
      late Directory folder;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp('lingfer-empty-reader-');
        await File('${folder.path}/empty.txt').writeAsString('  \n');
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => folder.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        await folder.delete(recursive: true);
      });
      await pumpReaderUi(
        tester,
        ReadingScreen(
          book: Book(
            title: '空资料',
            author: '',
            defaultLevel: VocabularyLevel.cet4,
            source: BookSource.localFile,
            locator: '${folder.path}/empty.txt',
          ),
        ),
      );
      for (var i = 0; i < 15 && find.text('暂时无法打开').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('暂时无法打开'), findsOneWidget);
      expect(find.textContaining('正文'), findsOneWidget);
      expect(find.text('返回重新导入'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
