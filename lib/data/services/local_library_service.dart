import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../domain/models/track.dart';
import '../local/database_helper.dart';

class LocalLibraryService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  List<Track> _tracks = [];
  bool _isScanning = false;
  String? _statusMessage;

  LocalLibraryService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance {
    loadLibrary();
  }

  List<Track> get tracks => List.unmodifiable(_tracks);
  bool get isScanning => _isScanning;
  String? get statusMessage => _statusMessage;

  Future<void> loadLibrary() async {
    try {
      await _autoSyncDownloadDirectory();
      _tracks = await _dbHelper.getLibraryTracks();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load local library: $e');
      }
    }
  }

  Future<void> _autoSyncDownloadDirectory() async {
    if (kIsWeb) return;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      final downloadDir = Directory(p.join(home, 'Music', 'CorePlayer'));
      if (!await downloadDir.exists()) return;

      const audioExtensions = {'.mp3', '.flac', '.ogg', '.wav', '.m4a', '.aac'};
      final existingTracks = await _dbHelper.getLibraryTracks();
      final existingPaths = existingTracks.map((t) => t.sourceUrl).toSet();

      final entities = downloadDir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext) && !existingPaths.contains(entity.path)) {
            final track = _createTrackFromFile(entity);
            await _dbHelper.addToLibrary(track);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocalLibraryService] _autoSyncDownloadDirectory error: $e');
      }
    }
  }

  Future<int> scanDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      _statusMessage = 'Directory not found: $directoryPath';
      notifyListeners();
      return 0;
    }

    _isScanning = true;
    _statusMessage = 'Scanning $directoryPath...';
    notifyListeners();

    int addedCount = 0;
    const audioExtensions = {'.mp3', '.flac', '.ogg', '.wav', '.m4a', '.aac'};

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            final track = _createTrackFromFile(entity);
            await _dbHelper.addToLibrary(track);
            addedCount++;
          }
        }
      }

      await loadLibrary();
      _statusMessage = 'Scan completed! Added $addedCount tracks.';
    } catch (e) {
      _statusMessage = 'Scan error: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }

    return addedCount;
  }

  Future<void> removeTrack(String trackId) async {
    final track = _tracks.where((t) => t.id == trackId).firstOrNull;
    if (track != null && track.sourceUrl.isNotEmpty) {
      try {
        final f = File(track.sourceUrl);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _dbHelper.removeFromLibrary(trackId);
    await loadLibrary();
  }

  Track _createTrackFromFile(File file) {
    final fileName = p.basenameWithoutExtension(file.path);
    String artist = 'Unknown Artist';
    String title = fileName;

    // Пытаемся распарсить стандартный шаблон "Исполнитель - Трек"
    if (fileName.contains(' - ')) {
      final parts = fileName.split(' - ');
      artist = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    }

    final fileStat = file.statSync();

    return Track(
      id: 'local_${file.path.hashCode}',
      providerId: 'local',
      title: title.isEmpty ? fileName : title,
      artist: artist,
      album: p.basename(p.dirname(file.path)),
      duration: Duration.zero,
      releaseDate: fileStat.modified,
      isExplicit: false,
      isStreamable: true,
      isDownloadable: false,
      sourceUrl: file.path,
    );
  }
}
