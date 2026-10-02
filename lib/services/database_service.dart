import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SshHost {
  final int? id;
  final String label;
  final String host;
  final int port;
  final String username;
  final String authType; // 'password' | 'key'
  final String? keyId;   // reference to key in secure storage

  SshHost({
    this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    this.keyId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'auth_type': authType,
        'key_id': keyId,
      };

  factory SshHost.fromMap(Map<String, dynamic> m) => SshHost(
        id: m['id'],
        label: m['label'],
        host: m['host'],
        port: m['port'],
        username: m['username'],
        authType: m['auth_type'],
        keyId: m['key_id'],
      );
}

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'vpngate.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE hosts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            host TEXT NOT NULL,
            port INTEGER NOT NULL DEFAULT 22,
            username TEXT NOT NULL,
            auth_type TEXT NOT NULL DEFAULT 'password',
            key_id TEXT
          )
        ''');
        await db.insert('hosts', {
          'label': '0i2.ru (Наш сервер)',
          'host': '0i2.ru',
          'port': 22,
          'username': 'root',
          'auth_type': 'key',
          'key_id': 'default_rsa_savun',
        });
      },
    );
  }

  static Future<List<SshHost>> getHosts() async {
    final db = await database;
    final rows = await db.query('hosts', orderBy: 'label ASC');
    return rows.map(SshHost.fromMap).toList();
  }

  static Future<int> insertHost(SshHost host) async {
    final db = await database;
    return db.insert('hosts', host.toMap()..remove('id'));
  }

  static Future<void> updateHost(SshHost host) async {
    final db = await database;
    await db.update('hosts', host.toMap(), where: 'id = ?', whereArgs: [host.id]);
  }

  static Future<void> deleteHost(int id) async {
    final db = await database;
    await db.delete('hosts', where: 'id = ?', whereArgs: [id]);
  }
}
