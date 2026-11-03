import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/image_prompt.dart';

class LocalCacheService {
  static const String _promptsKey = 'cached_prompts';
  static const String _promptsAtKey = 'cached_prompts_at';

  Future<void> savePrompts(List<ImagePrompt> prompts) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      prompts.map((p) => p.toMap()).toList(),
    );
    await prefs.setString(_promptsKey, encodedData);
    await prefs.setInt(_promptsAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// How old the saved prompt list is; null if it was never saved.
  Future<Duration?> promptsCacheAge() async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_promptsAtKey);
    if (at == null) return null;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
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
