import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class YouTubeProvider implements MusicProvider {
  final YoutubeExplode _yt;
  final bool _ownsClient;

  YouTubeProvider({YoutubeExplode? client})
      : _yt = client ?? YoutubeExplode(),
        _ownsClient = client == null;

  @override
  String get providerId => 'youtube';

  @override
  String get name => 'YouTube Music';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Try searchContent first
    try {
      final searchContentList = await _yt.search.searchContent(cleanQuery);
      final tracks = <Track>[];

      for (final item in searchContentList) {
        if (item is SearchVideo) {
          final thumb = item.thumbnails.isNotEmpty
              ? item.thumbnails.last.url.toString()
              : 'https://img.youtube.com/vi/${item.id.value}/hqdefault.jpg';

          tracks.add(Track(
            id: item.id.value,
            providerId: providerId,
            title: item.title,
            artist: item.author,
            duration: _parseDuration(item.duration),
            artworkUrl: thumb,
            isStreamable: true,
            isDownloadable: true,
            qualityOptions: const ['mp4', 'm4a', 'webm'],
            sourceUrl: 'https://www.youtube.com/watch?v=${item.id.value}',
          ));
        }
      }

      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}

    // Fallback to standard search
    try {
      final results = await _yt.search.search(cleanQuery);
      return results.map((video) {
        final thumb = video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : (video.thumbnails.standardResUrl.isNotEmpty
                ? video.thumbnails.standardResUrl
                : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg');

        return Track(
          id: video.id.value,
          providerId: providerId,
          title: video.title,
          artist: video.author,
          duration: video.duration ?? Duration.zero,
          artworkUrl: thumb,
          isStreamable: true,
          isDownloadable: true,
          qualityOptions: const ['mp4', 'm4a', 'webm'],
          sourceUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print('YouTube search error: $e');
      }
      return [];
    }
  }

  @override
  Future<Track?> getTrack(String id) async {
    try {
      final video = await _yt.videos.get(id);
      final thumb = video.thumbnails.highResUrl.isNotEmpty
          ? video.thumbnails.highResUrl
          : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

      return Track(
        id: video.id.value,
        providerId: providerId,
        title: video.title,
        artist: video.author,
        duration: video.duration ?? Duration.zero,
        artworkUrl: thumb,
        isStreamable: true,
        isDownloadable: true,
        qualityOptions: const ['mp4', 'm4a', 'webm'],
        sourceUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
      );
    } catch (e) {
      if (kDebugMode) {
        print('YouTube getTrack error for $id: $e');
      }
      return null;
    }
  }

  static Directory get cacheDir =>
      Directory(path.join(Directory.systemTemp.path, 'core_player_yt_cache'));

  static final Map<String, Future<String>> _inProgress = {};
  static final Map<String, String> _streamUrlCache = {};
  static final Map<String, DateTime> _streamUrlTimestamps = {};
  static const Duration _streamCacheTtl = Duration(minutes: 30);
  static bool? _ffmpegAvailable;

  static Future<bool> isFfmpegAvailable() async {
    if (_ffmpegAvailable != null) return _ffmpegAvailable!;
    try {
      final res = await Process.run('which', ['ffmpeg']);
      _ffmpegAvailable = res.exitCode == 0;
    } catch (_) {
      _ffmpegAvailable = false;
    }
    return _ffmpegAvailable!;
  }

  File _cacheFileFor(String trackId) =>
      File(path.join(cacheDir.path, '$trackId.m4a'));

  @override
  Future<String> getStreamUrl(Track track) async {
    // 1. Check in-memory stream URL cache (0 ms response for repeat / preloaded tracks)
    final cachedUrl = _streamUrlCache[track.id];
    final cachedTime = _streamUrlTimestamps[track.id];
    if (cachedUrl != null &&
        cachedTime != null &&
        DateTime.now().difference(cachedTime) < _streamCacheTtl) {
      return cachedUrl;
    }

    // 2. Check if extraction is already in flight
    if (_inProgress.containsKey(track.id)) {
      return _inProgress[track.id]!;
    }

    // 3. Check if clean audio is already cached on disk
    final cached = _cacheFileFor(track.id);
    if (await cached.exists()) {
      final length = await cached.length();
      if (length > 50000) {
        return cached.path;
      }
    }

    final future = _extractAudioTrack(track);
    _inProgress[track.id] = future;
    try {
      final result = await future;
      _streamUrlCache[track.id] = result;
      _streamUrlTimestamps[track.id] = DateTime.now();
      return result;
    } finally {
      _inProgress.remove(track.id);
    }
  }

  /// Preloads the audio track in background for queue gapless playback.
  Future<void> preloadTrack(Track track) async {
    try {
      final cached = _cacheFileFor(track.id);
      if (await cached.exists() && (await cached.length()) > 50000) {
        return;
      }
      if (_inProgress.containsKey(track.id)) {
        return;
      }
      getStreamUrl(track).catchError((_) => '');
    } catch (_) {}
  }

  /// Resolves pure high-bitrate audio stream URL (M4A/AAC/Opus) directly from YouTube.
  /// Starts streaming instantly (sub-second) without blocking on full file downloads.
  Future<String> _extractAudioTrack(Track track) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(VideoId(track.id));

      // 1. Prefer pure audio streams (highest bitrate, no video track, plays instantly in all engines)
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        return audioStreams.withHighestBitrate().url.toString();
      }

      // 2. Fallback to any audio stream
      final anyAudio = manifest.audio;
      if (anyAudio.isNotEmpty) {
        return anyAudio.first.url.toString();
      }

      // 3. Fallback to progressive muxed stream if no audio-only stream is present
      final muxedStreams = manifest.muxed;
      if (muxedStreams.isNotEmpty) {
        return muxedStreams.sortByVideoQuality().last.url.toString();
      }

      throw Exception('No playable audio streams found for YouTube track ${track.id}');
    } catch (e) {
      if (kDebugMode) {
        print('YouTube getStreamUrl error for ${track.id}: $e');
      }
      rethrow;
    }
  }

  /// Returns the progressive video stream URL (MP4) for the "Watch Video" feature.
  Future<String> getVideoStreamUrl(Track track) async {
    final manifest = await _yt.videos.streamsClient.getManifest(VideoId(track.id));
    final muxed = manifest.muxed;
    if (muxed.isNotEmpty) {
      return muxed.sortByVideoQuality().last.url.toString();
    }
    throw Exception('No video stream found for track ${track.id}');
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp4', 'm4a', 'webm'];

  @override
  Future<List<Track>> getUserLibrary() async => [];

  Duration _parseDuration(String? str) {
    if (str == null || str.isEmpty) return Duration.zero;
    final parts = str.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 2) {
      return Duration(minutes: parts[0], seconds: parts[1]);
    } else if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    } else if (parts.length == 1) {
      return Duration(seconds: parts[0]);
    }
    return Duration.zero;
  }

  void dispose() {
    if (_ownsClient) {
      _yt.close();
    }
  }
}
