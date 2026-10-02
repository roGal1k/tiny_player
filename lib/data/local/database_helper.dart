import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/track.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  Database? _customDb;

  DatabaseHelper._init();
  DatabaseHelper.withDatabase(Database db) : _customDb = db;

  static Future<DatabaseHelper> inMemory() async {
    final helper = DatabaseHelper._init();
    helper._customDb = await helper._initDB(inMemoryDatabasePath);
    return helper;
  }

  Future<Database> get database async {
    if (_customDb != null) return _customDb!;
    if (_database != null) return _database!;
    _database = await _initDB('core_player.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for Desktop
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String dbPath;
    if (filePath == inMemoryDatabasePath) {
      dbPath = inMemoryDatabasePath;
    } else {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        dbPath = join(appDocDir.path, 'CorePlayer', filePath);
        await Directory(dirname(dbPath)).create(recursive: true);
      } catch (_) {
        final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
        dbPath = join(home, '.core_player', filePath);
        await Directory(dirname(dbPath)).create(recursive: true);
      }
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createDB,
      ),
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE tracks (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT,
  artwork_url TEXT,
  duration_ms INTEGER NOT NULL,
  release_date TEXT,
  genre TEXT,
  is_explicit INTEGER NOT NULL,
  is_streamable INTEGER NOT NULL,
  is_downloadable INTEGER NOT NULL,
  quality_options TEXT,
  source_url TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE library (
  track_id TEXT PRIMARY KEY,
  added_at TEXT NOT NULL,
  FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
)
''');
  }

  Future<void> insertTrack(Track track) async {
    final db = await database;
    await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addToLibrary(Track track) async {
    final db = await database;
    await insertTrack(track);
    await db.insert(
      'library',
      {
        'track_id': track.id,
        'added_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFromLibrary(String trackId) async {
    final db = await database;
    await db.delete(
      'library',
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
  }

  Future<List<Track>> getLibraryTracks() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT t.* FROM tracks t
      INNER JOIN library l ON t.id = l.track_id
      ORDER BY l.added_at DESC
    ''');
    return result.map((json) => Track.fromMap(json)).toList();
  }

  Future<List<Track>> searchLocalTracks(String query) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT t.* FROM tracks t
      INNER JOIN library l ON t.id = l.track_id
      WHERE t.title LIKE ? OR t.artist LIKE ?
      ORDER BY t.title ASC
    ''', ['%$query%', '%$query%']);
    return result.map((json) => Track.fromMap(json)).toList();
  }

  Future<List<Track>> getAllTracks() async {
    final db = await database;
    final result = await db.query('tracks');
    return result.map((json) => Track.fromMap(json)).toList();
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }
}
