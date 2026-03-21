import 'package:flutter/material.dart';
import '../database/quiz_database.dart';
import '../models/word_entry.dart';
import '../models/word_group.dart';
import '../utils/word_utils.dart';
import 'quiz_page.dart';

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
  final Map<WordGroup, int> _learnedCounts = <WordGroup, int>{};

  @override
  void initState() {
    super.initState();
    _prepareDatabase();
  }

  Future<void> _prepareDatabase() async {
    try {
      for (final WordGroup group in WordGroup.values) {
        final List<WordEntry> words = await readWordsFromAsset(group.assetPath);
        if (words.length < 4) {
          throw StateError('Need at least 4 words in ${group.assetPath}.');
        }
        await QuizDatabase.instance.upsertAndLoadWords(group, words);
        final int count = await QuizDatabase.instance.getLearnedCount(group);
        _learnedCounts[group] = count;
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

  Future<void> _navigateToQuiz(WordGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizPage(group: group),
      ),
    );
    if (!mounted) {
      return;
    }
    // Refresh counts when returning
    final int count = await QuizDatabase.instance.getLearnedCount(group);
    setState(() {
      _learnedCounts[group] = count;
    });
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
      appBar: AppBar(
        title: const Text('Choose Word Group'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Progress',
            onPressed: () async {
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Reset Progress'),
                    content: const Text('Are you sure you want to wipe all progress?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Reset'),
                      ),
                    ],
                  );
                },
              );

              if (confirm == true && mounted) {
                setState(() {
                  _isPreparing = true;
                });
                await QuizDatabase.instance.resetDatabase();
                await _prepareDatabase();
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _GroupButton(
              label: 'Nouns',
              group: WordGroup.nouns,
              learnedCount: _learnedCounts[WordGroup.nouns] ?? 0,
              onPressed: () => _navigateToQuiz(WordGroup.nouns),
            ),
            const SizedBox(height: 12),
            _GroupButton(
              label: 'Verbs',
              group: WordGroup.verbs,
              learnedCount: _learnedCounts[WordGroup.verbs] ?? 0,
              onPressed: () => _navigateToQuiz(WordGroup.verbs),
            ),
            const SizedBox(height: 12),
            _GroupButton(
              label: 'Objectives',
              group: WordGroup.objectives,
              learnedCount: _learnedCounts[WordGroup.objectives] ?? 0,
              onPressed: () => _navigateToQuiz(WordGroup.objectives),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.label,
    required this.group,
    required this.learnedCount,
    required this.onPressed,
  });

  final String label;
  final WordGroup group;
  final int learnedCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          if (learnedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$learnedCount learned',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
