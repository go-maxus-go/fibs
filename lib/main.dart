import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MainApp());
}

class WordEntry {
  const WordEntry({
    required this.index,
    required this.de,
    required this.en,
    required this.ru,
    this.seenCount = 0,
    this.correctCount = 0,
  });

  final int index;
  final String de;
  final String en;
  final String ru;
  final int seenCount;
  final int correctCount;

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
  }) {
    return WordEntry(
      index: index,
      de: de,
      en: en,
      ru: ru,
      seenCount: seenCount ?? this.seenCount,
      correctCount: correctCount ?? this.correctCount,
    );
  }
}

enum QuizDirection {
  germanToEnRu,
  enRuToGerman,
}

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

class QuizDatabase {
  QuizDatabase._();

  static final QuizDatabase instance = QuizDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    final String dbPath = path.join(await getDatabasesPath(), 'quiz_state.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE group_stats (
            group_name TEXT PRIMARY KEY,
            streak INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE words (
            group_name TEXT NOT NULL,
            word_index INTEGER NOT NULL,
            de TEXT NOT NULL,
            en TEXT NOT NULL,
            ru TEXT NOT NULL,
            seen_count INTEGER NOT NULL DEFAULT 0,
            correct_count INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(group_name, word_index)
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<WordEntry>> upsertAndLoadWords(
    WordGroup group,
    List<WordEntry> jsonWords,
  ) async {
    final Database db = await database;
    final Batch batch = db.batch();
    for (final WordEntry word in jsonWords) {
      batch.rawInsert(
        '''
        INSERT INTO words (group_name, word_index, de, en, ru, seen_count, correct_count)
        VALUES (?, ?, ?, ?, ?, 0, 0)
        ON CONFLICT(group_name, word_index) DO UPDATE SET
          de = excluded.de,
          en = excluded.en,
          ru = excluded.ru
        ''',
        <Object>[
          group.dbKey,
          word.index,
          word.de,
          word.en,
          word.ru,
        ],
      );
    }
    await batch.commit(noResult: true);

    final List<Map<String, Object?>> rows = await db.query(
      'words',
      where: 'group_name = ?',
      whereArgs: <Object>[group.dbKey],
    );
    final Map<int, Map<String, Object?>> byIndex = <int, Map<String, Object?>>{
      for (final Map<String, Object?> row in rows)
        (row['word_index'] as int): row,
    };

    return jsonWords.map((WordEntry word) {
      final Map<String, Object?>? row = byIndex[word.index];
      if (row == null) {
        return word;
      }
      return word.copyWith(
        seenCount: row['seen_count'] as int,
        correctCount: row['correct_count'] as int,
      );
    }).toList();
  }

  Future<int> getStreak(WordGroup group) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'group_stats',
      columns: <String>['streak'],
      where: 'group_name = ?',
      whereArgs: <Object>[group.dbKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['streak'] as int;
  }

  Future<void> setStreak(WordGroup group, int streak) async {
    final Database db = await database;
    await db.insert(
      'group_stats',
      <String, Object>{
        'group_name': group.dbKey,
        'streak': streak,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> incrementSeen(WordGroup group, int wordIndex) async {
    final Database db = await database;
    await db.rawUpdate(
      '''
      UPDATE words
      SET seen_count = seen_count + 1
      WHERE group_name = ? AND word_index = ?
      ''',
      <Object>[group.dbKey, wordIndex],
    );
  }

  Future<void> incrementCorrect(WordGroup group, int wordIndex) async {
    final Database db = await database;
    await db.rawUpdate(
      '''
      UPDATE words
      SET correct_count = correct_count + 1
      WHERE group_name = ? AND word_index = ?
      ''',
      <Object>[group.dbKey, wordIndex],
    );
  }
}

Future<List<WordEntry>> _readWordsFromAsset(String assetPath) async {
  final String raw = await rootBundle.loadString(assetPath);
  final List<dynamic> parsed = jsonDecode(raw) as List<dynamic>;
  return parsed
      .map((dynamic e) => WordEntry.fromJson(e as Map<String, dynamic>))
      .where(
        (WordEntry e) =>
            e.index > 0 && e.de.isNotEmpty && e.en.isNotEmpty && e.ru.isNotEmpty,
      )
      .toList();
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const GroupSelectionPage(),
    );
  }
}

class GroupSelectionPage extends StatelessWidget {
  const GroupSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _GroupSelectionView();
  }
}

class _GroupSelectionView extends StatefulWidget {
  const _GroupSelectionView();

  @override
  State<_GroupSelectionView> createState() => _GroupSelectionViewState();
}

class _GroupSelectionViewState extends State<_GroupSelectionView> {
  bool _isPreparing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareDatabase();
  }

  Future<void> _prepareDatabase() async {
    try {
      for (final WordGroup group in WordGroup.values) {
        final List<WordEntry> words = await _readWordsFromAsset(group.assetPath);
        if (words.length < 4) {
          throw StateError('Need at least 4 words in ${group.assetPath}.');
        }
        await QuizDatabase.instance.upsertAndLoadWords(group, words);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
        _error = 'Could not prepare local database.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose Word Group')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isPreparing = true;
                      _error = null;
                    });
                    _prepareDatabase();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Word Group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<QuizPage>(
                    builder: (_) => const QuizPage(group: WordGroup.nouns),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: const Text('Nouns'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<QuizPage>(
                    builder: (_) => const QuizPage(group: WordGroup.verbs),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: const Text('Verbs'),
            ),
          ],
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.group,
  });

  final WordGroup group;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const String _idkOption = "I don't know";

  final Random _random = Random();

  List<WordEntry> _words = <WordEntry>[];
  String? _currentPrompt;
  String? _currentCorrectAnswer;
  WordEntry? _currentWord;
  List<String> _options = <String>[];
  QuizDirection? _direction;
  int _correctStreak = 0;
  bool _isLoading = true;
  bool _isChecking = false;
  bool _answersRevealed = false;
  final Set<String> _wrongSelections = <String>{};
  String? _correctSelection;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    try {
      final List<WordEntry> words = await _readWordsFromAsset(widget.group.assetPath);

      if (words.length < 4) {
        throw StateError('Need at least 4 words to build options.');
      }

      final List<WordEntry> persistedWords = await QuizDatabase.instance
          .upsertAndLoadWords(widget.group, words);
      final int storedStreak = await QuizDatabase.instance.getStreak(widget.group);

      if (!mounted) {
        return;
      }
      setState(() {
        _words = persistedWords;
        _correctStreak = storedStreak;
        _isLoading = false;
      });
      await _nextQuestion();
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load words from ${widget.group.assetPath}.';
      });
    }
  }

  Future<void> _nextQuestion() async {
    if (_words.length < 4) {
      return;
    }

    final WordEntry chosen = _words[_random.nextInt(_words.length)];
    final QuizDirection direction = _random.nextBool()
        ? QuizDirection.germanToEnRu
        : QuizDirection.enRuToGerman;
    final String correctAnswer = direction == QuizDirection.germanToEnRu
        ? chosen.enRu
        : chosen.de;
    final Set<String> options = <String>{correctAnswer};

    while (options.length < 4) {
      final WordEntry distractor = _words[_random.nextInt(_words.length)];
      options.add(
        direction == QuizDirection.germanToEnRu ? distractor.enRu : distractor.de,
      );
    }

    final List<String> shuffled = options.toList()..shuffle(_random);
    final List<String> optionsWithIdk = <String>[
      ...shuffled,
      _idkOption,
    ];

    await QuizDatabase.instance.incrementSeen(widget.group, chosen.index);

    if (!mounted) {
      return;
    }
    setState(() {
      _direction = direction;
      _currentPrompt = direction == QuizDirection.germanToEnRu
          ? chosen.de
          : chosen.enRu;
      _currentWord = chosen.copyWith(seenCount: chosen.seenCount + 1);
      _currentCorrectAnswer = correctAnswer;
      _options = optionsWithIdk;
      _isChecking = false;
      _answersRevealed = false;
      _wrongSelections.clear();
      _correctSelection = null;
    });
  }

  Future<void> _onOptionTap(String selected) async {
    if (_currentCorrectAnswer == null || _isChecking) {
      return;
    }

    final bool isCorrect = selected == _currentCorrectAnswer;
    if (!isCorrect) {
      setState(() {
        _correctStreak = 0;
        _wrongSelections.add(selected);
      });
      await QuizDatabase.instance.setStreak(widget.group, 0);
      return;
    }

    setState(() {
      _correctStreak += 1;
      _isChecking = true;
      _correctSelection = selected;
    });
    if (_currentWord != null) {
      await QuizDatabase.instance.incrementCorrect(widget.group, _currentWord!.index);
    }
    await QuizDatabase.instance.setStreak(widget.group, _correctStreak);

    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _nextQuestion();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('German ${widget.group.title} Quiz')),
        body: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final String? promptWord = _currentPrompt;
    final QuizDirection? direction = _direction;
    if (promptWord == null || direction == null) {
      return const Scaffold(
        body: Center(child: Text('No word available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('German ${widget.group.title} Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Streak: $_correctStreak',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Text(
              direction == QuizDirection.germanToEnRu
                  ? 'Pick the right English (Russian):'
                  : 'Pick the right German word:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              promptWord,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!_answersRevealed)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      _answersRevealed = true;
                    });
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: Text(
                        'Tap to show answers',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                ),
              )
            else
              for (final String option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ElevatedButton(
                    onPressed: () => _onOptionTap(option),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: _correctSelection == option
                          ? Colors.green
                          : _wrongSelections.contains(option)
                          ? Colors.red
                          : null,
                    ),
                    child: Text(option),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
