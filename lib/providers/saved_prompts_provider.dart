import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/image_prompt.dart';

final savedPromptsProvider = StateNotifierProvider<SavedPromptsNotifier, List<ImagePrompt>>((ref) {
  return SavedPromptsNotifier();
});

class SavedPromptsNotifier extends StateNotifier<List<ImagePrompt>> {
  static const String _savedKey = 'saved_prompts_list';

  SavedPromptsNotifier() : super([]) {
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_savedKey);
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        state = decoded.map((item) => ImagePrompt.fromJson(item)).toList();
      }
    } catch (e) {
      // Fallback if parsing fails
      state = [];
    }
  }

  Future<void> toggleSave(ImagePrompt prompt) async {
    final exists = state.any((p) => p.id == prompt.id);
    if (exists) {
      state = state.where((p) => p.id != prompt.id).toList();
    } else {
      state = [prompt, ...state];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(state.map((p) => p.toMap()).toList());
      await prefs.setString(_savedKey, encoded);
    } catch (e) {
      // Error saving
    }
  }

  bool isSaved(String promptId) {
    return state.any((p) => p.id == promptId);
  }
}
