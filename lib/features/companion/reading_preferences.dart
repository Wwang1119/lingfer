enum ReadingLanguage {
  auto('auto', '自动识别', 'chinese'),
  zh('zh', '中文', 'chinese'),
  en('en', '英语', 'latin'),
  ja('ja', '日语', 'japanese'),
  ko('ko', '韩语', 'korean'),
  fr('fr', '法语', 'latin'),
  de('de', '德语', 'latin'),
  es('es', '西班牙语', 'latin'),
  pt('pt', '葡萄牙语', 'latin'),
  it('it', '意大利语', 'latin'),
  hi('hi', '印地语', 'devanagari');

  const ReadingLanguage(this.code, this.label, this.script);
  final String code;
  final String label;
  final String script;

  static ReadingLanguage parse(
    Object? value, {
    ReadingLanguage fallback = en,
  }) => values.where((v) => v.code == value).firstOrNull ?? fallback;
}

enum GeneralDifficulty {
  basic('基础', 'A1–A2'),
  intermediate('进阶', 'B1–B2'),
  advanced('高阶', 'C1–C2');

  const GeneralDifficulty(this.label, this.reference);
  final String label;
  final String reference;
}

enum ReadingMode {
  learning('学习辅助'),
  translation('整页对照');

  const ReadingMode(this.label);
  final String label;
}

class ReadingPreferences {
  const ReadingPreferences({
    this.source = ReadingLanguage.auto,
    this.target = ReadingLanguage.zh,
    this.automatic = true,
    this.difficulty = GeneralDifficulty.intermediate,
    this.mode = ReadingMode.learning,
  });

  final ReadingLanguage source;
  final ReadingLanguage target;
  final bool automatic;
  final GeneralDifficulty difficulty;
  final ReadingMode mode;
  bool get usesEnglishVocabulary =>
      source == ReadingLanguage.en ||
      source == ReadingLanguage.auto ||
      target == ReadingLanguage.en;
  String get directionLabel => '${source.label} → ${target.label}';
  bool get needsOnlineTranslation =>
      source != ReadingLanguage.en || target != ReadingLanguage.zh;

  ReadingPreferences copyWith({
    ReadingLanguage? source,
    ReadingLanguage? target,
    bool? automatic,
    GeneralDifficulty? difficulty,
    ReadingMode? mode,
  }) => ReadingPreferences(
    source: source ?? this.source,
    target: (target ?? this.target) == ReadingLanguage.auto
        ? ReadingLanguage.zh
        : target ?? this.target,
    automatic: automatic ?? this.automatic,
    difficulty: difficulty ?? this.difficulty,
    mode: mode ?? this.mode,
  );

  Map<String, Object?> toJson() => {
    'sourceLanguage': source.code,
    'targetLanguage': target.code,
    'automatic': automatic,
    'generalDifficulty': difficulty.name,
    'readingMode': mode.name,
  };

  factory ReadingPreferences.fromJson(Map raw) => ReadingPreferences(
    mode: raw['readingMode'] == 'translation'
        ? ReadingMode.translation
        : ReadingMode.learning,
    source: ReadingLanguage.parse(
      raw['sourceLanguage'],
      fallback: ReadingLanguage.auto,
    ),
    target:
        ReadingLanguage.parse(
              raw['targetLanguage'],
              fallback: ReadingLanguage.zh,
            ) ==
            ReadingLanguage.auto
        ? ReadingLanguage.zh
        : ReadingLanguage.parse(
            raw['targetLanguage'],
            fallback: ReadingLanguage.zh,
          ),
    automatic: raw['automatic'] != false,
    difficulty:
        GeneralDifficulty.values
            .where((v) => v.name == raw['generalDifficulty'])
            .firstOrNull ??
        GeneralDifficulty.intermediate,
  );
}
