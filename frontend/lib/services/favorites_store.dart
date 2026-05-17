import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FavoriteItemsStore {
  static const String _key = 'favorite_items';

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      return decoded;
    } catch (_) {
      await prefs.remove(_key);
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  Future<bool> isFavorite(int itemId) async {
    final items = await load();
    return items.any((i) => (i['id'] as num?)?.toInt() == itemId);
  }

  Future<void> toggle(Map<String, dynamic> item) async {
    final items = await load();
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final exists = items.indexWhere((i) => (i['id'] as num?)?.toInt() == id);
    if (exists >= 0) {
      items.removeAt(exists);
    } else {
      items.add({
        'id': id,
        'title': item['title'],
        'price_per_day': item['price_per_day'],
        'location_text': item['location_text'],
        'owner_name': item['owner_name'],
        'rating': item['rating'],
      });
    }
    await _save(items);
  }

  Future<void> remove(int itemId) async {
    final items = await load();
    items.removeWhere((i) => (i['id'] as num?)?.toInt() == itemId);
    await _save(items);
  }
}
