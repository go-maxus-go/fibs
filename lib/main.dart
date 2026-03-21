import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MainApp());
}

class WordEntry {
  const WordEntry({
    required this.de,
    required this.en,
  });

  final String de;
  final String en;

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    return WordEntry(
      de: (json['de'] as String?)?.trim() ?? '',
      en: (json['en'] as String?)?.trim() ?? '',
    );
  }
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
      home: const QuizPage(),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final Random _random = Random();

  List<WordEntry> _words = <WordEntry>[];
  WordEntry? _currentWord;
  List<String> _options = <String>[];
  int _correctCount = 0;
  bool _isLoading = true;
  bool _isChecking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    try {
      final String raw = await rootBundle.loadString('data/nouns.json');
      final List<dynamic> parsed = jsonDecode(raw) as List<dynamic>;
      final List<WordEntry> words = parsed
          .map((dynamic e) => WordEntry.fromJson(e as Map<String, dynamic>))
          .where((WordEntry e) => e.de.isNotEmpty && e.en.isNotEmpty)
          .toList();

      if (words.length < 4) {
        throw StateError('Need at least 4 words to build options.');
      }

      setState(() {
        _words = words;
        _isLoading = false;
      });
      _nextQuestion();
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load words from data/nouns.json.';
      });
    }
  }

  void _nextQuestion() {
    if (_words.length < 4) {
      return;
    }

    final WordEntry chosen = _words[_random.nextInt(_words.length)];
    final Set<String> options = <String>{chosen.en};

    while (options.length < 4) {
      options.add(_words[_random.nextInt(_words.length)].en);
    }

    final List<String> shuffled = options.toList()..shuffle(_random);

    setState(() {
      _currentWord = chosen;
      _options = shuffled;
      _isChecking = false;
    });
  }

  void _onOptionTap(String selected) {
    if (_currentWord == null || _isChecking) {
      return;
    }

    final bool isCorrect = selected == _currentWord!.en;
    if (!isCorrect) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Try again.')),
      );
      return;
    }

    setState(() {
      _correctCount += 1;
      _isChecking = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Correct!'),
        duration: Duration(milliseconds: 450),
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 500), () {
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
        appBar: AppBar(title: const Text('German Nouns Quiz')),
        body: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final WordEntry? word = _currentWord;
    if (word == null) {
      return const Scaffold(
        body: Center(child: Text('No word available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('German Nouns Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Correct: $_correctCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Text(
              'What is the translation of:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              word.de,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            for (final String option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  onPressed: () => _onOptionTap(option),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
