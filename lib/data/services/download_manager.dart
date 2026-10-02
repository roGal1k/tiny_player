import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/models/track.dart';
import '../local/database_helper.dart';
import '../providers/provider_registry.dart';
import 'local_library_service.dart';

enum DownloadStatus { downloading, completed, failed }

class DownloadTask {
  final Track track;
  double progress;
  DownloadStatus status;
  String? error;
  String? savedFilePath;
  int downloadedBytes;
  int totalBytes;

  DownloadTask({
    required this.track,
    this.progress = 0.0,
    this.status = DownloadStatus.downloading,
    this.error,
    this.savedFilePath,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  });
}

class DownloadManager extends ChangeNotifier {
  final ProviderRegistry registry;
  final LocalLibraryService libraryService;
  final DatabaseHelper _dbHelper;
  final http.Client _client;

  final Map<String, DownloadTask> _tasks = {};

  DownloadManager({
    required this.registry,
    required this.libraryService,
    DatabaseHelper? dbHelper,
    http.Client? client,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _client = client ?? http.Client();

  List<DownloadTask> get tasks => _tasks.values.toList().reversed.toList();

  DownloadTask? getTask(String trackId) => _tasks[trackId];

  int get activeDownloadsCount =>
      _tasks.values.where((t) => t.status == DownloadStatus.downloading).length;

  int get completedDownloadsCount =>
      _tasks.values.where((t) => t.status == DownloadStatus.completed).length;

  bool isDownloading(Track track) {
    final taskKey = '${track.providerId}_${track.id}';
    return _tasks[taskKey]?.status == DownloadStatus.downloading;
  }

  bool isDownloaded(Track track) {
    final taskKey = '${track.providerId}_${track.id}';
    return _tasks[taskKey]?.status == DownloadStatus.completed;
  }

  /// Пакетное скачивание списка треков (пропускает уже скачанные или находящиеся в процессе)
  Future<int> downloadTracks(List<Track> tracks) async {
    final downloadable = tracks.where((t) => t.isDownloadable).toList();
    int scheduled = 0;
    for (final track in downloadable) {
      final taskKey = '${track.providerId}_${track.id}';
      if (_tasks[taskKey]?.status == DownloadStatus.completed ||
          _tasks[taskKey]?.status == DownloadStatus.downloading) {
        continue;
      }
      await downloadTrack(track);
      scheduled++;
    }
    return scheduled;
  }

  /// Скачивание всех доступных треков из переданного списка
  Future<int> downloadAll(List<Track> tracks) => downloadTracks(tracks);

  /// Скачивание первых N доступных треков (например, топ-5 или топ-10)
  Future<int> downloadTopN(List<Track> tracks, int n) {
    final topTracks = tracks.where((t) => t.isDownloadable).take(n).toList();
    return downloadTracks(topTracks);
  }

  Future<String> _getDownloadDirectory() async {
    // На Linux и Desktop отдаем приоритет папке Music пользователя
    final home = Platform.environment['HOME'];
    if (home != null && Directory(home).existsSync()) {
      final musicDir = Directory(p.join(home, 'Music', 'CorePlayer'));
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }
      return musicDir.path;
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(p.join(appDocDir.path, 'Music'));
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    return fallbackDir.path;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  Future<void> downloadTrack(Track track) async {
    final taskKey = '${track.providerId}_${track.id}';
    if (_tasks.containsKey(taskKey) &&
        (_tasks[taskKey]!.status == DownloadStatus.downloading ||
            _tasks[taskKey]!.status == DownloadStatus.completed)) {
      return; // Уже скачивается или уже скачан
    }

    final task = DownloadTask(track: track);
    _tasks[taskKey] = task;
    notifyListeners();

    try {
      final provider = registry.activeProviders.firstWhere(
        (p) => p.providerId == track.providerId,
        orElse: () => throw Exception('Provider ${track.providerId} not found'),
      );

      final streamUrl = await provider.getStreamUrl(track);
      if (streamUrl.isEmpty) {
        throw Exception('Download URL not available');
      }

      final downloadDir = await _getDownloadDirectory();
      final safeArtist = _sanitizeFileName(track.artist);
      final safeTitle = _sanitizeFileName(track.title);
      final fileName = '$safeArtist - $safeTitle.mp3';
      final filePath = p.join(downloadDir, fileName);
      final targetFile = File(filePath);

      final client = _client;
      final isHls = streamUrl.contains('.m3u8') || streamUrl.contains('/hls');

      if (isHls) {
        // Скачиваем HLS плейлист и склеиваем сегменты
        final playlistResponse = await client.get(Uri.parse(streamUrl));
        if (playlistResponse.statusCode != 200) {
          throw Exception('Failed to load HLS playlist: ${playlistResponse.statusCode}');
        }

        final lines = playlistResponse.body.split('\n');
        final segmentUris = <Uri>[];
        final baseUri = Uri.parse(streamUrl);

        for (var line in lines) {
          line = line.trim();
          if (line.isNotEmpty && !line.startsWith('#')) {
            segmentUris.add(baseUri.resolve(line));
          }
        }

        if (segmentUris.isEmpty) {
          throw Exception('No audio segments found in HLS stream');
        }

        final sink = targetFile.openWrite();
        for (int i = 0; i < segmentUris.length; i++) {
          final segRes = await client.get(segmentUris[i]);
          if (segRes.statusCode == 200) {
            sink.add(segRes.bodyBytes);
            task.downloadedBytes += segRes.bodyBytes.length;
            task.progress = (i + 1) / segmentUris.length;
            notifyListeners();
          }
        }
        await sink.flush();
        await sink.close();
      } else {
        // Прямой прогрессивный HTTP поток (MP3/WAV/OGG/AAC)
        final request = http.Request('GET', Uri.parse(streamUrl));
        final response = await client.send(request);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          task.totalBytes = response.contentLength ?? 0;
          final sink = targetFile.openWrite();

          await response.stream.listen((chunk) {
            sink.add(chunk);
            task.downloadedBytes += chunk.length;
            if (task.totalBytes > 0) {
              task.progress = (task.downloadedBytes / task.totalBytes).clamp(0.0, 1.0);
            }
            notifyListeners();
          }).asFuture();

          await sink.flush();
          await sink.close();
        } else {
          throw Exception('Download HTTP failed: ${response.statusCode}');
        }
      }

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.savedFilePath = filePath;

      // Автоматически индексируем скачанный файл в локальную библиотеку
      final localTrack = Track(
        id: 'local_${filePath.hashCode}',
        providerId: 'local',
        title: track.title,
        artist: track.artist,
        album: track.album ?? 'CorePlayer Downloads',
        artworkUrl: track.artworkUrl,
        duration: track.duration,
        releaseDate: DateTime.now(),
        isExplicit: track.isExplicit,
        isStreamable: true,
        isDownloadable: false,
        sourceUrl: filePath,
      );

      await _dbHelper.addToLibrary(localTrack);
      await libraryService.loadLibrary();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
    } finally {
      notifyListeners();
    }
  }
}
