class WordEntry {
  const WordEntry({
    required this.index,
    required this.de,
    required this.en,
    required this.ru,
    this.seenCount = 0,
    this.correctCount = 0,
    this.streak = 0,
    this.queueIndex,
  });

  final int index;
  final String de;
  final String en;
  final String ru;
  final int seenCount;
  final int correctCount;
  final int streak;
  final int? queueIndex;

  String get enRu => '$en ($ru)';

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    return WordEntry(
      index: (json['index'] as int?) ?? -1,
      de: (json['de'] as String?)?.trim() ?? '',
      en: (json['en'] as String?)?.trim() ?? '',
      ru: (json['ru'] as String?)?.trim() ?? '',
    );
  }

  WordEntry copyWith({
    int? seenCount,
    int? correctCount,
    int? streak,
    int? queueIndex,
  }) {
    return WordEntry(
      index: index,
      de: de,
      en: en,
      ru: ru,
      seenCount: seenCount ?? this.seenCount,
      correctCount: correctCount ?? this.correctCount,
      streak: streak ?? this.streak,
      queueIndex: queueIndex ?? this.queueIndex,
    );
  }
}
