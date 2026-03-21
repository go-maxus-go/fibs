enum WordGroup {
  nouns,
  verbs,
  objectives,
}

extension WordGroupConfig on WordGroup {
  String get title {
    switch (this) {
      case WordGroup.nouns:
        return 'Nouns';
      case WordGroup.verbs:
        return 'Verbs';
      case WordGroup.objectives:
        return 'Objectives';
    }
  }

  String get assetPath {
    switch (this) {
      case WordGroup.nouns:
        return 'data/nouns.json';
      case WordGroup.verbs:
        return 'data/verbs.json';
      case WordGroup.objectives:
        return 'data/objectives.json';
    }
  }

  String get dbKey {
    switch (this) {
      case WordGroup.nouns:
        return 'nouns';
      case WordGroup.verbs:
        return 'verbs';
      case WordGroup.objectives:
        return 'objectives';
    }
  }
}
