import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/image_prompt.dart';

class LocalCacheService {
  static const String _promptsKey = 'cached_prompts';

  Future<void> savePrompts(List<ImagePrompt> prompts) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      prompts.map((p) => p.toMap()).toList(),
    );
    await prefs.setString(_promptsKey, encodedData);
  }

  Future<List<ImagePrompt>> getCachedPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString(_promptsKey);
    
    if (encodedData != null) {
      final List<dynamic> decodedData = jsonDecode(encodedData);
      return decodedData.map((item) => ImagePrompt.fromJson(item)).toList();
    }
    return [];
  }
}
