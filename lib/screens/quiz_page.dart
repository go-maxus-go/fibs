import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import '../database/quiz_database.dart';
import '../models/word_entry.dart';
import '../models/word_group.dart';
import '../utils/word_utils.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.group,
    required this.lang1,
    required this.lang2,
  });

  final WordGroup group;
  final String lang1;
  final String lang2;

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
  String? _currentPromptLang;
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

  Future<void> _pronounce(String text, String lang) async {
    String ttsLang = 'en-US';
    String spdLang = 'en';
    
    if (lang == 'DE') {
      ttsLang = 'de-DE';
      spdLang = 'de';
    } else if (lang == 'RU') {
      ttsLang = 'ru-RU';
      spdLang = 'ru';
    }

    String textToSpeak = text.split('(').first.trim();

    if (Platform.isLinux) {
      try {
        await Process.run('spd-say', <String>['-l', spdLang, textToSpeak]);
      } catch (e) {
        debugPrint('Could not run spd-say: $e');
      }
    } else {
      await _flutterTts.setLanguage(ttsLang);
      await _flutterTts.speak(textToSpeak);
    }
  }

  int fibonacciIndex(int index) {
    if (index == 0) {
      return 0;
    }
    if (index <= 2) {
      return 1;
    }
    int a = 1;
    int b = 1;
    for (int i = 2; i < index; i++) {
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
    final bool firstLangPrompt = _random.nextBool();
    final String promptLang = firstLangPrompt ? widget.lang1 : widget.lang2;
    final String answerLang = firstLangPrompt ? widget.lang2 : widget.lang1;
    
    final String correctAnswer = chosen.getText(answerLang);
    final Set<String> options = <String>{correctAnswer};

    while (options.length < 4) {
      final WordEntry distractor = _words[_random.nextInt(_words.length)];
      options.add(distractor.getText(answerLang));
    }

    final List<String> shuffled = options.toList()..shuffle(_random);
    final List<String> optionsWithIdk = <String>[...shuffled, _idkOption];

    await QuizDatabase.instance.incrementSeen(widget.group, chosen.index);

    if (!mounted) {
      return;
    }
    setState(() {
      _currentPromptLang = promptLang;
      _currentPrompt = chosen.getText(promptLang);
      _currentWord = chosen.copyWith(seenCount: chosen.seenCount + 1);
      _currentCorrectAnswer = correctAnswer;
      _options = optionsWithIdk;
      _isChecking = false;
      _answersRevealed = _autoRevealAnswers;
      _madeMistakeOnCurrent = false;
      _wrongSelections.clear();
      _correctSelection = null;
    });

    if (_isWordHidden && _currentPrompt != null && _currentPromptLang != null) {
      _pronounce(_currentPrompt!, _currentPromptLang!);
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
            int insertIndex = fibonacciIndex(5 + streak);
            if (updatedWord.status == WordStatus.easy) {
              insertIndex = fibonacciIndex((9 + streak * 1.5).round());
            } else if (updatedWord.status == WordStatus.hard) {
              insertIndex = fibonacciIndex((5 + streak / 1.5).round());
            }
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

  Future<void> _setStatus(WordStatus status) async {
    if (_currentWord == null) return;

    final WordEntry updatedWord = _currentWord!.copyWith(status: status);
    setState(() {
      _currentWord = updatedWord;
      if (_activeQueue.isNotEmpty &&
          _activeQueue.first.index == updatedWord.index) {
        _activeQueue[0] = updatedWord;
      }
    });

    await QuizDatabase.instance.setWordStatus(
      widget.group,
      updatedWord.index,
      status,
    );
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
    final String? promptLang = _currentPromptLang;
    if (promptWord == null || promptLang == null) {
      return const Scaffold(body: Center(child: Text('No word available.')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.lang1}-${widget.lang2} ${widget.group.title} Quiz')),
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
            const Spacer(),
            Column(
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
                if (_currentWord != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.fitness_center),
                          color: _currentWord!.status == WordStatus.hard
                              ? Colors.red
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          tooltip: 'Mark as Hard',
                          onPressed: () {
                            _setStatus(
                              _currentWord!.status == WordStatus.hard
                                  ? WordStatus.normal
                                  : WordStatus.hard,
                            );
                          },
                        ),
                        const SizedBox(width: 32),
                        IconButton(
                          icon: const Icon(Icons.eco),
                          color: _currentWord!.status == WordStatus.easy
                              ? Colors.green
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          tooltip: 'Mark as Easy',
                          onPressed: () {
                            _setStatus(
                              _currentWord!.status == WordStatus.easy
                                  ? WordStatus.normal
                                  : WordStatus.easy,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _isWordHidden ? Icons.visibility_off : Icons.visibility,
                      ),
                      tooltip: _isWordHidden ? 'Show word' : 'Hide word',
                      onPressed: () {
                        setState(() {
                          _isWordHidden = !_isWordHidden;
                        });
                        if (_isWordHidden &&
                            _currentPrompt != null &&
                            _currentPromptLang != null) {
                          _pronounce(_currentPrompt!, _currentPromptLang!);
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
                          _answersRevealed = _autoRevealAnswers;
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
                      onPressed: () => _pronounce(promptWord, promptLang),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Stack(
                  children: <Widget>[
                    Opacity(
                      opacity: _answersRevealed ? 1.0 : 0.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final String option in _options)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                onPressed: _answersRevealed
                                    ? () => _onOptionTap(option)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
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
                    if (!_answersRevealed)
                      Positioned.fill(
                        bottom: 12,
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
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
