class WordGroup {
  const WordGroup({
    required this.title,
    required this.assetPath,
    required this.dbKey,
  });

  final String title;
  final String assetPath;
  final String dbKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordGroup &&
          runtimeType == other.runtimeType &&
          dbKey == other.dbKey;

  @override
  int get hashCode => dbKey.hashCode;
}
