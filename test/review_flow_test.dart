import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingfer/features/companion/companion_controller.dart';
import 'package:lingfer/features/companion/companion_review.dart';
import 'package:lingfer/features/companion/review_schedule.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';

const word = VocabularyHit(
  entry: VocabularyEntry(
    word: 'maintain',
    translation: '维持；主张',
    tags: {'cet4'},
  ),
  surface: 'maintain',
  context: 'Researchers maintain that practice matters.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Review survives reopening, becomes due later, and does not mark a word known',
    () async {
      final now = DateTime.utc(2026, 11, 8, 6);
      final first = CompanionController();
      await first.initialize();
      await first.save(word);
      expect(
        first.dueWords(at: now).map((w) => w.studyKey),
        contains('maintain'),
      );
      await first.gradeReview('maintain', RecallRating.remembered, at: now);
      expect(first.known, isEmpty);
      first.dispose();
      final reopened = CompanionController();
      await reopened.initialize();
      expect(reopened.saved, contains('maintain'));
      expect(
        reopened.dueWords(at: now.add(const Duration(hours: 23))),
        isEmpty,
      );
      expect(reopened.dueWords(at: now.add(const Duration(days: 1))).length, 1);
      await reopened.gradeReview(
        'maintain',
        RecallRating.again,
        at: now.add(const Duration(days: 1)),
      );
      expect(
        reopened.dueWords(at: now.add(const Duration(days: 1, minutes: 9))),
        isEmpty,
      );
      expect(
        reopened
            .dueWords(at: now.add(const Duration(days: 1, minutes: 10)))
            .length,
        1,
      );
      expect(reopened.reviews['maintain']!.reviews, 2);
      reopened.dispose();
    },
  );

  test(
    'Backup transfers learning progress, merges safely and excludes runtime settings',
    () async {
      final origin = CompanionController();
      await origin.initialize();
      await origin.save(word);
      await origin.gradeReview(
        'maintain',
        RecallRating.remembered,
        at: DateTime.utc(2026, 11, 8),
      );
      final backup = origin.exportLearningBackup();
      final data = jsonDecode(backup) as Map;
      expect(data.keys.toSet(), {
        'format',
        'version',
        'exportedAt',
        'saved',
        'known',
        'reviews',
      });
      final target = CompanionController();
      await target.initialize();
      target.saved.clear();
      target.reviews.clear();
      expect(await target.importLearningBackup(backup), 1);
      expect(await target.importLearningBackup(backup), 0);
      expect(target.reviews['maintain']!.reviews, 1);
      target.saved.clear();
      data['known'] = 'invalid';
      await expectLater(
        target.importLearningBackup(jsonEncode(data)),
        throwsFormatException,
      );
      expect(target.saved, isEmpty);
      origin.dispose();
      target.dispose();
    },
  );

  testWidgets(
    'Narrow large-text review hides answer until revealed and completes one rating',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CompanionController();
      controller.saved[word.studyKey] = word;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: CompanionReviewPage(controller: controller),
        ),
      );
      expect(find.text('维持；主张'), findsNothing);
      await tester.ensureVisible(find.text('查看答案'));
      await tester.tap(find.text('查看答案'));
      await tester.pumpAndSettle();
      expect(find.text('维持；主张'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('认识'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('认识'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('认识'));
      await tester.pumpAndSettle();
      expect(find.text('这轮复习完成了'), findsOneWidget);
      expect(controller.known, isEmpty);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
