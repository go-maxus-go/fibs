import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import '../database/quiz_database.dart';
import '../models/quiz_direction.dart';
import '../models/word_entry.dart';
import '../models/word_group.dart';
import '../utils/word_utils.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.group});

  final WordGroup group;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const String _idkOption = "I don't know";

  final Random _random = Random();
  final FlutterTts _flutterTts = FlutterTts();

  List<WordEntry> _words = <WordEntry>[];
  List<WordEntry> _activeQueue = <WordEntry>[];

  String? _currentPrompt;
  String? _currentCorrectAnswer;
  WordEntry? _currentWord;
  List<String> _options = <String>[];
  QuizDirection? _direction;
  int _correctStreak = 0;
  bool _isLoading = true;
  bool _isChecking = false;
  bool _answersRevealed = false;
  bool _madeMistakeOnCurrent = false;
  bool _isWordHidden = false;
  bool _autoRevealAnswers = false;
  final Set<String> _wrongSelections = <String>{};
  String? _correctSelection;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void dispose() {
    if (!Platform.isLinux) {
      _flutterTts.stop();
    }
    super.dispose();
  }

  Future<void> _pronounce(String text, QuizDirection direction) async {
    String lang = 'de-DE';
    String spdLang = 'de';
    String textToSpeak = text;
    if (direction == QuizDirection.enRuToGerman) {
      lang = 'en-US';
      spdLang = 'en';
      textToSpeak = text.split('(').first.trim();
    }

    if (Platform.isLinux) {
      try {
        await Process.run('spd-say', <String>['-l', spdLang, textToSpeak]);
      } catch (e) {
        debugPrint('Could not run spd-say: $e');
      }
    } else {
      await _flutterTts.setLanguage(lang);
      await _flutterTts.speak(textToSpeak);
    }
  }

  int fibonacciIndex(int index) {
    int a = 1;
    int b = 1;
    for (int i = 0; i < index; i++) {
      int c = a + b;
      a = b;
      b = c;
    }

    return b;
  }

  Future<void> _loadWords() async {
    try {
      final List<WordEntry> words = await readWordsFromAsset(
        widget.group.assetPath,
      );

      if (words.length < 4) {
        throw StateError('Need at least 4 words to build options.');
      }

      final List<WordEntry> persistedWords = await QuizDatabase.instance
          .upsertAndLoadWords(widget.group, words);
      final int storedStreak = await QuizDatabase.instance.getStreak(
        widget.group,
      );

      persistedWords.sort(
        (WordEntry a, WordEntry b) =>
            (a.queueIndex ?? a.index).compareTo(b.queueIndex ?? b.index),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _words = List<WordEntry>.from(persistedWords);
        _activeQueue = List<WordEntry>.from(persistedWords);
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
    if (_activeQueue.isEmpty) {
      return;
    }

    final WordEntry chosen = _activeQueue.first;
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
        direction == QuizDirection.germanToEnRu
            ? distractor.enRu
            : distractor.de,
      );
    }

    final List<String> shuffled = options.toList()..shuffle(_random);
    final List<String> optionsWithIdk = <String>[...shuffled, _idkOption];

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
      _answersRevealed = _autoRevealAnswers;
      _madeMistakeOnCurrent = false;
      _wrongSelections.clear();
      _correctSelection = null;
    });

    if (_isWordHidden && _currentPrompt != null && _direction != null) {
      _pronounce(_currentPrompt!, _direction!);
    }
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
        _madeMistakeOnCurrent = true;
      });
      await QuizDatabase.instance.setStreak(widget.group, 0);
      return;
    }

    setState(() {
      if (!_madeMistakeOnCurrent) {
        _correctStreak += 1;
      }
      _isChecking = true;
      _correctSelection = selected;
    });

    if (_currentWord != null && !_madeMistakeOnCurrent) {
      await QuizDatabase.instance.incrementCorrect(
        widget.group,
        _currentWord!.index,
      );
    }
    await QuizDatabase.instance.setStreak(widget.group, _correctStreak);

    Future<void>.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        if (_activeQueue.isNotEmpty) {
          final WordEntry word = _activeQueue.removeAt(0);

          WordEntry updatedWord;
          if (!_madeMistakeOnCurrent) {
            final int streak = word.streak + 1;
            updatedWord = word.copyWith(streak: streak);
            int insertIndex = fibonacciIndex(streak + 2);
            if (insertIndex > _activeQueue.length) {
              insertIndex = _activeQueue.length;
            }
            _activeQueue.insert(insertIndex, updatedWord);
          } else {
            updatedWord = word.copyWith(streak: 0);
            int insertIndex = 5;
            if (insertIndex > _activeQueue.length) {
              insertIndex = _activeQueue.length;
            }
            _activeQueue.insert(insertIndex, updatedWord);
          }
          await QuizDatabase.instance.updateQueue(widget.group, _activeQueue);
        }
        _nextQuestion();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('German ${widget.group.title} Quiz')),
        body: Center(child: Text(_errorMessage!, textAlign: TextAlign.center)),
      );
    }

    final String? promptWord = _currentPrompt;
    final QuizDirection? direction = _direction;
    if (promptWord == null || direction == null) {
      return const Scaffold(body: Center(child: Text('No word available.')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('German ${widget.group.title} Quiz')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Streak: $_correctStreak',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _isWordHidden
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Text(
                            promptWord,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Text(
                          promptWord,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        icon: Icon(
                          _isWordHidden
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        tooltip: _isWordHidden ? 'Show word' : 'Hide word',
                        onPressed: () {
                          setState(() {
                            _isWordHidden = !_isWordHidden;
                          });
                          if (_isWordHidden &&
                              _currentPrompt != null &&
                              _direction != null) {
                            _pronounce(_currentPrompt!, _direction!);
                          }
                        },
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: Icon(
                          _autoRevealAnswers ? Icons.lock_open : Icons.lock,
                        ),
                        tooltip: _autoRevealAnswers
                            ? 'Disable auto-reveal'
                            : 'Enable auto-reveal',
                        onPressed: () {
                          setState(() {
                            _autoRevealAnswers = !_autoRevealAnswers;
                            if (_autoRevealAnswers) {
                              _answersRevealed = true;
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy word',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: promptWord));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: const Icon(Icons.volume_up, size: 24),
                        tooltip: 'Pronounce word',
                        onPressed: () => _pronounce(promptWord, direction),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (!_answersRevealed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
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
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                            child: Center(
                              child: Text(
                                'Tap to show answers',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
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
          ],
        ),
      ),
    );
  }
}
