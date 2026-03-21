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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<QuizPage>(
                    builder: (_) => const QuizPage(group: WordGroup.objectives),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: const Text('Objectives'),
            ),
          ],
        ),
      ),
    );
  }
}
