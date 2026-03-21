enum WordGroup {
  nouns,
  verbs,
}

extension WordGroupConfig on WordGroup {
  String get title => this == WordGroup.nouns ? 'Nouns' : 'Verbs';

  String get assetPath =>
      this == WordGroup.nouns ? 'data/nouns.json' : 'data/verbs.json';

  String get dbKey => this == WordGroup.nouns ? 'nouns' : 'verbs';
}
