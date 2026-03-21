import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/word_entry.dart';

Future<List<WordEntry>> readWordsFromAsset(String assetPath) async {
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
