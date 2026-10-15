import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/track.dart';
import '../../domain/models/artist.dart';

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
    String dbPath;

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      dbPath = filePath;
    } else {
      // Initialize FFI for Desktop
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

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
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _onConfigureDB,
        onCreate: _createDB,
        onOpen: _onOpenDB,
      ),
    );
  }

  Future _onConfigureDB(Database db) async {
    if (!kIsWeb) {
      try {
        await db.execute('PRAGMA foreign_keys = ON;');
        final path = db.path;
        if (path != inMemoryDatabasePath && path != ':memory:') {
          await db.execute('PRAGMA journal_mode = WAL;');
          await db.execute('PRAGMA synchronous = NORMAL;');
          await db.execute('PRAGMA cache_size = -8000;');
        }
      } catch (e) {
        debugPrint('[DatabaseHelper] PRAGMA tuning notice: $e');
      }
    }
  }

  Future _onOpenDB(Database db, [int? version]) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS tracks (
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
CREATE TABLE IF NOT EXISTS library (
  track_id TEXT PRIMARY KEY,
  added_at TEXT NOT NULL,
  FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS cached_tracks (
  track_id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  cached_at TEXT NOT NULL,
  FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS favorite_artists (
  name TEXT PRIMARY KEY,
  artwork_url TEXT,
  added_at TEXT NOT NULL
);
''');

    // Performance indexes for fast joins, searches, and provider filtering
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_provider ON tracks(provider_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_library_added ON library(added_at DESC);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_tracks ON cached_tracks(track_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_favorite_artists_added ON favorite_artists(added_at DESC);');
  }

  Future _createDB(Database db, int version) async {
    await _onOpenDB(db, version);
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
    final cleanQuery = query.trim();

    if (cleanQuery.isEmpty) {
      final result = await db.rawQuery('''
        SELECT DISTINCT t.* FROM tracks t
        WHERE t.id IN (SELECT track_id FROM library)
           OR t.id IN (SELECT track_id FROM cached_tracks)
           OR t.provider_id = 'local'
        ORDER BY t.title ASC
      ''');
      return result.map((json) => Track.fromMap(json)).toList();
    }

    final result = await db.rawQuery('''
      SELECT DISTINCT t.* FROM tracks t
      WHERE (
        t.id IN (SELECT track_id FROM library)
        OR t.id IN (SELECT track_id FROM cached_tracks)
        OR t.provider_id = 'local'
      )
      AND (t.title LIKE ? OR t.artist LIKE ? OR t.album LIKE ?)
      ORDER BY t.title ASC
    ''', ['%$cleanQuery%', '%$cleanQuery%', '%$cleanQuery%']);
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

  // -------------------------------------------------------------
  // Audio Cache Methods
  // -------------------------------------------------------------

  Future<void> _ensureCachedTracksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_tracks (
        track_id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        cached_at TEXT NOT NULL,
        FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> addToCache(Track track, String filePath, int fileSize) async {
    final db = await database;
    await _ensureCachedTracksTable(db);
    await insertTrack(track);
    await db.insert(
      'cached_tracks',
      {
        'track_id': track.id,
        'file_path': filePath,
        'file_size': fileSize,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFromCache(String trackId) async {
    final db = await database;
    await _ensureCachedTracksTable(db);
    await db.delete(
      'cached_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> clearCachedTracks() async {
    final db = await database;
    await _ensureCachedTracksTable(db);
    await db.delete('cached_tracks');
  }

  Future<List<Track>> getCachedTracks() async {
    final db = await database;
    await _ensureCachedTracksTable(db);
    final result = await db.rawQuery('''
      SELECT t.*, c.file_path, c.file_size, c.cached_at FROM tracks t
      INNER JOIN cached_tracks c ON t.id = c.track_id
      ORDER BY c.cached_at DESC
    ''');
    return result.map((json) => Track.fromMap(json)).toList();
  }

  Future<bool> isTrackCached(String trackId) async {
    final db = await database;
    await _ensureCachedTracksTable(db);
    final maps = await db.query(
      'cached_tracks',
      columns: ['track_id'],
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  // --- Favorite Artists ---
  Future<void> addFavoriteArtist(Artist artist) async {
    final db = await database;
    await db.insert(
      'favorite_artists',
      artist.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavoriteArtist(String name) async {
    final db = await database;
    await db.delete(
      'favorite_artists',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
    );
  }

  Future<List<Artist>> getFavoriteArtists() async {
    final db = await database;
    final maps = await db.query(
      'favorite_artists',
      orderBy: 'added_at DESC',
    );
    return maps.map((m) => Artist.fromMap(m)).toList();
  }

  Future<bool> isFavoriteArtist(String name) async {
    final db = await database;
    final maps = await db.query(
      'favorite_artists',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  // -------------------------------------------------------------
  // Full User Data File Export & Import (VPS & Local Backups)
  // -------------------------------------------------------------

  Future<Map<String, dynamic>> exportFullUserData() async {
    final libraryTracks = await getLibraryTracks();
    final favoriteArtists = await getFavoriteArtists();
    final db = await database;
    final settingsList = await db.query('settings');
    final settingsMap = <String, String>{
      for (final row in settingsList)
        (row['key'] as String): (row['value'] as String),
    };

    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'library': libraryTracks.map((t) => t.toMap()).toList(),
      'favorite_artists': favoriteArtists.map((a) => a.toMap()).toList(),
      'settings': settingsMap,
    };
  }

  Future<int> importFullUserData(Map<String, dynamic> data) async {
    int importedCount = 0;

    // 1. Tracks (Library)
    final rawLibrary = (data['library'] ?? data['tracks']) as List?;
    if (rawLibrary != null) {
      for (final item in rawLibrary) {
        if (item is Map<String, dynamic>) {
          try {
            final track = Track.fromMap(item);
            await addToLibrary(track);
            importedCount++;
          } catch (_) {}
        }
      }
    }

    // 2. Favorite Artists
    final rawArtists = (data['artists'] ?? data['favorite_artists']) as List?;
    if (rawArtists != null) {
      for (final item in rawArtists) {
        if (item is Map<String, dynamic>) {
          try {
            final artist = Artist.fromMap(item);
            await addFavoriteArtist(artist);
            importedCount++;
          } catch (_) {}
        }
      }
    }

    // 3. Settings
    final rawSettings = data['settings'] as Map<String, dynamic>?;
    if (rawSettings != null) {
      for (final entry in rawSettings.entries) {
        try {
          await setSetting(entry.key, entry.value.toString());
        } catch (_) {}
      }
    }

    return importedCount;
  }
}


