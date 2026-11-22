import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One autosave slot, written at the start of every day.
class SaveService {
  static const String _key = 'village_market_save_v1';

  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> && data['day'] is int) return data;
    } catch (_) {}
    return null;
  }

  static Future<void> save(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
