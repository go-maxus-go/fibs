import 'dart:math';
import 'package:flutter/material.dart';
import '../database/quiz_database.dart';
import '../models/quiz_direction.dart';
import '../models/word_entry.dart';
import '../models/word_group.dart';
import '../utils/word_utils.dart';

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
      final List<WordEntry> words = await readWordsFromAsset(widget.group.assetPath);

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
