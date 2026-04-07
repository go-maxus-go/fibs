import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
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
  List<WordGroup> _groups = <WordGroup>[];
  final Map<WordGroup, int> _learnedCounts = <WordGroup, int>{};
  final Map<WordGroup, int> _totalCounts = <WordGroup, int>{};
  final List<String> _availableLanguages = <String>['EN', 'DE', 'RU'];
  final Set<String> _selectedLanguages = <String>{'DE', 'EN'};

  @override
  void initState() {
    super.initState();
    _prepareDatabase();
  }

  Future<void> _prepareDatabase() async {
    try {
      final String yamlString = await rootBundle.loadString('data/groups.yaml');
      final YamlMap yaml = loadYaml(yamlString) as YamlMap;
      final YamlList groupsList = yaml['groups'] as YamlList;

      final List<WordGroup> parsedGroups = <WordGroup>[];
      for (final dynamic item in groupsList) {
        final YamlMap groupMap = item as YamlMap;
        parsedGroups.add(
          WordGroup(
            title: groupMap['title'] as String,
            assetPath: groupMap['assetPath'] as String,
            dbKey: groupMap['dbKey'] as String,
          ),
        );
      }

      for (final WordGroup group in parsedGroups) {
        final List<WordEntry> words = await readWordsFromAsset(group.assetPath);
        if (words.length < 4) {
          throw StateError('Need at least 4 words in ${group.assetPath}.');
        }
        await QuizDatabase.instance.upsertAndLoadWords(group, words);
        final int learned = await QuizDatabase.instance.getLearnedCount(group);
        final int total = await QuizDatabase.instance.getTotalCount(group);
        _learnedCounts[group] = learned;
        _totalCounts[group] = total;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = parsedGroups;
        _isPreparing = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
        _error = 'Could not prepare local database: $e';
      });
    }
  }

  Future<void> _navigateToQuiz(WordGroup group) async {
    if (_selectedLanguages.length != 2) return;
    final List<String> langs = _selectedLanguages.toList();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizPage(
          group: group,
          lang1: langs[0],
          lang2: langs[1],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    // Refresh counts when returning
    final int learned = await QuizDatabase.instance.getLearnedCount(group);
    final int total = await QuizDatabase.instance.getTotalCount(group);
    setState(() {
      _learnedCounts[group] = learned;
      _totalCounts[group] = total;
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Select exactly 2 languages:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _availableLanguages.map((String lang) {
                return FilterChip(
                  label: Text(lang),
                  selected: _selectedLanguages.contains(lang),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        if (_selectedLanguages.length == 2) {
                          _selectedLanguages.remove(_selectedLanguages.first);
                        }
                        _selectedLanguages.add(lang);
                      } else {
                        _selectedLanguages.remove(lang);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_selectedLanguages.length != 2)
              const Text(
                'Please select exactly 2 languages to continue.',
                style: TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: _groups.map((WordGroup group) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupButton(
                      label: group.title,
                      group: group,
                      learnedCount: _learnedCounts[group] ?? 0,
                      totalCount: _totalCounts[group] ?? 0,
                      onPressed: _selectedLanguages.length == 2
                          ? () => _navigateToQuiz(group)
                          : null,
                      onReset: () async {
                        final bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Reset Group'),
                              content: Text('Are you sure you want to wipe all progress for "${group.title}"?'),
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
                          await QuizDatabase.instance.resetGroup(group);
                          await _prepareDatabase();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
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
    required this.totalCount,
    required this.onPressed,
    required this.onReset,
  });

  final String label;
  final WordGroup group;
  final int learnedCount;
  final int totalCount;
  final VoidCallback? onPressed;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(label),
                if (totalCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'learned $learnedCount/$totalCount',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: 'Reset Group Progress',
          onPressed: onReset,
        ),
      ],
    );
  }
}
