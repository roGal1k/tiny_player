import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';
import '../local/database_helper.dart';

class AudioCacheService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final http.Client _client;
  final String _cacheDir;

  final Set<String> _cachedTrackIds = {};
  final Map<String, String> _cachedFilePaths = {};
  final Set<String> _inFlightCacheTasks = {};

  AudioCacheService({
    DatabaseHelper? dbHelper,
    http.Client? client,
    String? customCacheDir,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _client = client ?? http.Client(),
        _cacheDir = customCacheDir ?? defaultCacheDir;

  static String get defaultCacheDir {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.cache', 'core_player', 'audio_cache');
    }
    return p.join(Directory.systemTemp.path, 'core_player_audio_cache');
  }

  String get cacheDir => _cacheDir;
  int get cachedCount => _cachedTrackIds.length;

  Future<void> init() async {
    try {
      final dir = Directory(_cacheDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 1. Scan filesystem for completed files
      await _syncFromDisk();

      // 2. Load from database
      final dbTracks = await _dbHelper.getCachedTracks();
      for (final t in dbTracks) {
        if (t.sourceUrl.isNotEmpty && File(t.sourceUrl).existsSync()) {
          _cachedTrackIds.add(t.id);
          _cachedFilePaths[t.id] = t.sourceUrl;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[AudioCacheService] init error: $e');
    }
  }

  Future<void> _syncFromDisk() async {
    try {
      final dir = Directory(_cacheDir);
      if (!await dir.exists()) return;

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.part')) {
          final filename = p.basenameWithoutExtension(entity.path);
          final underscoreIdx = filename.indexOf('_');
          if (underscoreIdx > 0 && underscoreIdx < filename.length - 1) {
            final trackId = filename.substring(underscoreIdx + 1);
            if (entity.lengthSync() > 4096) {
              _cachedTrackIds.add(trackId);
              _cachedFilePaths[trackId] = entity.path;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AudioCacheService] _syncFromDisk error: $e');
    }
  }

  String _cacheKeyForTrack(Track track) {
    final sanitizedId = track.id.replaceAll(RegExp(r'[^\w\.-]'), '_');
    return '${track.providerId}_$sanitizedId';
  }

  String _cachePathForTrack(Track track, {String extension = 'mp3'}) {
    final key = _cacheKeyForTrack(track);
    return p.join(_cacheDir, '$key.$extension');
  }

  bool isCached(Track track) {
    if (_cachedTrackIds.contains(track.id)) return true;
    final file = getCachedFile(track);
    return file != null;
  }

  File? getCachedFile(Track track) {
    // Check in-memory path
    final memoryPath = _cachedFilePaths[track.id];
    if (memoryPath != null) {
      final f = File(memoryPath);
      if (f.existsSync() && f.lengthSync() > 4096) {
        return f;
      }
    }

    // Check standard .mp3
    final mp3File = File(_cachePathForTrack(track, extension: 'mp3'));
    if (mp3File.existsSync() && mp3File.lengthSync() > 4096) {
      _cachedTrackIds.add(track.id);
      _cachedFilePaths[track.id] = mp3File.path;
      return mp3File;
    }

    // Check standard .m4a
    final m4aFile = File(_cachePathForTrack(track, extension: 'm4a'));
    if (m4aFile.existsSync() && m4aFile.lengthSync() > 4096) {
      _cachedTrackIds.add(track.id);
      _cachedFilePaths[track.id] = m4aFile.path;
      return m4aFile;
    }

    // Check YouTube specific cache if applicable
    if (track.providerId == 'youtube') {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final ytCacheFile = File(p.join(home, '.cache', 'core_player_yt_cache', '${track.id}.m4a'));
        if (ytCacheFile.existsSync() && ytCacheFile.lengthSync() > 4096) {
          _cachedTrackIds.add(track.id);
          _cachedFilePaths[track.id] = ytCacheFile.path;
          return ytCacheFile;
        }
      }
    }

    return null;
  }

  Future<void> registerExistingLocalFile(Track track, String localPath) async {
    try {
      final f = File(localPath);
      if (await f.exists() && await f.length() > 4096) {
        _cachedTrackIds.add(track.id);
        _cachedFilePaths[track.id] = localPath;
        await _dbHelper.addToCache(
          track.copyWith(sourceUrl: localPath),
          localPath,
          await f.length(),
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<File?> cacheTrackInBackground(Track track, String streamUrl) async {
    if (isCached(track)) {
      return getCachedFile(track);
    }

    if (_inFlightCacheTasks.contains(track.id)) {
      return null;
    }

    // If streamUrl is already a local file, register it
    if (!streamUrl.startsWith('http://') && !streamUrl.startsWith('https://')) {
      await registerExistingLocalFile(track, streamUrl);
      return File(streamUrl);
    }

    _inFlightCacheTasks.add(track.id);

    try {
      final dir = Directory(_cacheDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = streamUrl.toLowerCase().contains('.m4a') || track.providerId == 'youtube'
          ? 'm4a'
          : 'mp3';
      final finalPath = _cachePathForTrack(track, extension: ext);
      final partPath = '$finalPath.part';
      final partFile = File(partPath);

      if (await partFile.exists()) {
        await partFile.delete();
      }

      final uri = Uri.parse(streamUrl);
      final request = http.Request('GET', uri);
      request.headers.addAll({
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'X-Forwarded-For': '85.249.20.1',
      });

      final streamedResponse = await _client.send(request);
      if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
        final sink = partFile.openWrite();
        await streamedResponse.stream.pipe(sink);
        await sink.close();

        final fileSize = await partFile.length();
        if (fileSize > 4096) {
          final finalFile = await partFile.rename(finalPath);
          _cachedTrackIds.add(track.id);
          _cachedFilePaths[track.id] = finalFile.path;

          await _dbHelper.addToCache(
            track.copyWith(sourceUrl: finalFile.path),
            finalFile.path,
            fileSize,
          );

          notifyListeners();
          debugPrint('[AudioCacheService] Successfully cached "${track.title}" ($fileSize bytes) -> $finalPath');
          return finalFile;
        } else {
          if (await partFile.exists()) await partFile.delete();
        }
      }
    } catch (e) {
      debugPrint('[AudioCacheService] cacheTrackInBackground failed for "${track.title}": $e');
    } finally {
      _inFlightCacheTasks.remove(track.id);
    }

    return null;
  }

  Future<void> preloadTrack(Track track, MusicProvider provider) async {
    if (isCached(track)) return;
    try {
      final streamUrl = await provider.getStreamUrl(track);
      if (streamUrl.isNotEmpty) {
        await cacheTrackInBackground(track, streamUrl);
      }
    } catch (e) {
      debugPrint('[AudioCacheService] preloadTrack error: $e');
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = Directory(_cacheDir);
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
      _cachedTrackIds.clear();
      _cachedFilePaths.clear();
      await _dbHelper.clearCachedTracks();
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioCacheService] clearCache error: $e');
    }
  }

  int get totalCacheSizeBytes {
    try {
      final dir = Directory(_cacheDir);
      if (!dir.existsSync()) return 0;
      int total = 0;
      for (final entity in dir.listSync()) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Track>> getCachedTracks() async {
    return _dbHelper.getCachedTracks();
  }

  Future<void> removeTrackFromCache(Track track) async {
    try {
      final file = getCachedFile(track);
      if (file != null && await file.exists()) {
        await file.delete();
      }
      _cachedTrackIds.remove(track.id);
      _cachedFilePaths.remove(track.id);
      await _dbHelper.removeFromCache(track.id);
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioCacheService] removeTrackFromCache error: $e');
    }
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
