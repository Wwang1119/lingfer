/// Local review progress is separate from saved words and explicit known words.
/// A self-rating never silently removes a word from reading assistance.
enum RecallRating { again, remembered, easy }

class ReviewProgress {
  const ReviewProgress({
    required this.due,
    this.streak = 0,
    this.reviews = 0,
    this.lastReviewed,
  });
  final DateTime due;
  final int streak;
  final int reviews;
  final DateTime? lastReviewed;

  ReviewProgress grade(RecallRating rating, DateTime now) {
    final nextStreak = rating == RecallRating.again
        ? 0
        : (streak + 1).clamp(1, 6);
    const intervals = [1, 3, 7, 14, 30, 60];
    final delay = rating == RecallRating.again
        ? const Duration(minutes: 10)
        : Duration(
            days: rating == RecallRating.easy
                ? intervals[nextStreak.clamp(1, 5)]
                : intervals[nextStreak - 1],
          );
    return ReviewProgress(
      due: now.add(delay),
      streak: nextStreak,
      reviews: reviews + 1,
      lastReviewed: now,
    );
  }

  Map<String, Object?> toJson() => {
    'due': due.toUtc().toIso8601String(),
    'streak': streak,
    'reviews': reviews,
    'lastReviewed': lastReviewed?.toUtc().toIso8601String(),
  };
  static ReviewProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final due = DateTime.tryParse(value['due']?.toString() ?? '');
    if (due == null) return null;
    return ReviewProgress(
      due: due,
      streak: ((value['streak'] as num?)?.toInt() ?? 0).clamp(0, 6),
      reviews: ((value['reviews'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
      lastReviewed: DateTime.tryParse(value['lastReviewed']?.toString() ?? ''),
    );
  }
}
