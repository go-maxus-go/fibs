import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/word_entry.dart';
import '../models/word_group.dart';

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
