import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/track.dart';
import '../providers/provider_registry.dart';
import '../providers/youtube_provider.dart';
import 'audio_cache_service.dart';
import 'settings_service.dart';

/// Manages prioritized background preloading of upcoming tracks in the active playlist.
///
/// Ensures the currently playing track always has maximum network bandwidth priority:
/// 1. Delaying background preloads until initial playback buffering is complete (e.g. 3.5s delay).
/// 2. Instant cancellation of stale preload queues whenever the user skips or chooses a new track.
/// 3. Polite sequential processing (1 track at a time with throttled intervals).
class TrackPreloadManager {
  final ProviderRegistry registry;
  final AudioCacheService? cacheService;
  final SettingsService? settingsService;

  int _sessionEpoch = 0;
  Timer? _delayTimer;
  bool _isDisposed = false;
  bool _isPaused = false;
  bool _isRunningQueue = false;
  String? _currentlyPreloadingTrackId;
  final Duration throttleDuration;

  TrackPreloadManager({
    required this.registry,
    this.cacheService,
    this.settingsService,
    this.throttleDuration = const Duration(milliseconds: 400),
  });

  bool get isPreloading => _isRunningQueue || _currentlyPreloadingTrackId != null;
  String? get currentPreloadingTrackId => _currentlyPreloadingTrackId;

  /// Schedules preloading for the next up to [maxTracks] (default: 10) in [queue].
  void schedulePreload({
    required List<Track> queue,
    required int currentIndex,
    bool isRepeatAll = false,
    int maxTracks = 10,
    Duration startDelay = const Duration(milliseconds: 3500),
  }) {
    if (_isDisposed) return;
    if (kIsWeb) return;
    if (settingsService?.autoCacheAudio == false) return;
    if (cacheService == null) return;

    // Invalidate any ongoing preload jobs immediately
    cancel();

    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) {
      return;
    }

    final tracksToPreload = <Track>[];
    final total = queue.length;

    for (int step = 1; step <= maxTracks && step < total; step++) {
      int nextIdx = currentIndex + step;
      if (nextIdx >= total) {
        if (isRepeatAll) {
          nextIdx = nextIdx % total;
        } else {
          break;
        }
      }
      if (nextIdx == currentIndex) break;
      final candidate = queue[nextIdx];
      // Avoid duplicate tracks in preload batch
      if (!tracksToPreload.any((t) => t.id == candidate.id)) {
        tracksToPreload.add(candidate);
      }
    }

    if (tracksToPreload.isEmpty) return;

    final currentSession = _sessionEpoch;

    // Start background preloading after startDelay
    _delayTimer = Timer(startDelay, () {
      if (_isDisposed || currentSession != _sessionEpoch) return;
      _runPreloadQueue(tracksToPreload, currentSession);
    });
  }

  /// Cancels any scheduled or active background preloading.
  void cancel() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _sessionEpoch++;
    _isRunningQueue = false;
    _currentlyPreloadingTrackId = null;
  }

  /// Temporarily pauses preloading (e.g. while current track is buffering).
  void pause() {
    _isPaused = true;
  }

  /// Resumes preloading if it was paused.
  void resume() {
    _isPaused = false;
  }

  Future<void> _runPreloadQueue(List<Track> tracks, int sessionEpoch) async {
    _isRunningQueue = true;
    try {
      for (final track in tracks) {
        if (_isDisposed || sessionEpoch != _sessionEpoch) {
          debugPrint('[TrackPreloadManager] Preload cancelled by newer session.');
          break;
        }

        while (_isPaused && !_isDisposed && sessionEpoch == _sessionEpoch) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        if (_isDisposed || sessionEpoch != _sessionEpoch) break;

        // Skip if already cached
        if (cacheService!.isCached(track)) {
          continue;
        }

        _currentlyPreloadingTrackId = track.id;

        try {
          // 1. YouTube specific preload
          if (track.providerId == 'youtube') {
            try {
              final yt = registry.allProviders.whereType<YouTubeProvider>().firstOrNull;
              yt?.preloadTrack(track);
            } catch (_) {}
          }

          // 2. Resolve stream URL
          final provider = registry.allProviders
              .where((p) => p.providerId.toLowerCase() == track.providerId.toLowerCase())
              .firstOrNull;

          if (provider != null) {
            final streamUrl = await provider.getStreamUrl(track);

            // Verify session is still valid after network resolve
            if (_isDisposed || sessionEpoch != _sessionEpoch) break;

            if (streamUrl.isNotEmpty) {
              await cacheService!.cacheTrackInBackground(track, streamUrl);
            }
          }
        } catch (e) {
          debugPrint('[TrackPreloadManager] Error preloading "${track.title}": $e');
        } finally {
          if (_currentlyPreloadingTrackId == track.id) {
            _currentlyPreloadingTrackId = null;
          }
        }

        // Small throttling delay between background tracks to prevent provider rate limiting
        if (!_isDisposed && sessionEpoch == _sessionEpoch && throttleDuration > Duration.zero) {
          await Future.delayed(throttleDuration);
        }
      }
    } finally {
      if (_sessionEpoch == sessionEpoch) {
        _isRunningQueue = false;
        _currentlyPreloadingTrackId = null;
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    cancel();
  }
}
