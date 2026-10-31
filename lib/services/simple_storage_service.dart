import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Простой файловый storage для macOS (без Keychain).
/// На Android/iOS используется flutter_secure_storage.
class SimpleStorageService {
  static Map<String, String>? _cache;
  static const _fileName = 'app_storage.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> _load() async {
    if (_cache != null) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final map = json.decode(raw) as Map<String, dynamic>;
        _cache = map.map((k, v) => MapEntry(k, v.toString()));
      } else {
        _cache = {};
      }
    } catch (_) {
      _cache = {};
    }
  }

  static Future<void> _save() async {
    try {
      final file = await _getFile();
      await file.writeAsString(json.encode(_cache));
    } catch (_) {}
  }

  static Future<String?> read(String key) async {
    await _load();
    return _cache![key];
  }

  static Future<void> write(String key, String value) async {
    await _load();
    _cache![key] = value;
    await _save();
  }

  static Future<void> delete(String key) async {
    await _load();
    _cache!.remove(key);
    await _save();
  }
}
