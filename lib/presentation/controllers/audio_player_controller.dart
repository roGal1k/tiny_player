import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../domain/models/track.dart';
import '../../data/providers/provider_registry.dart';
import '../../data/providers/youtube_provider.dart';
import '../../data/services/equalizer_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/audio_cache_service.dart';
import '../../data/services/core_audio_handler.dart';
import '../../data/services/web_proxy_helper.dart';
import '../../data/services/web_media_session_helper.dart';

enum PlaybackRepeatMode {
  off,
  all,
  one,
}

class AudioPlayerController extends ChangeNotifier {
  final ProviderRegistry registry;
  final EqualizerService? equalizerService;
  final SettingsService? settingsService;
  final AudioCacheService? cacheService;
  final CoreAudioHandler? audioHandler;
  final AudioPlayer _player;

  Track? _currentTrack;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  double _baseVolume = 1.0;
  bool _isMuted = false;
  int _consecutiveErrors = 0;

  // Queue / Playlist state
  final List<Track> _queue = [];
  int _currentIndex = -1;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;
  bool _isShuffle = false;

  // Sleep timer state
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  bool _sleepAtEndOfTrack = false;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  AudioPlayerController({
    required this.registry,
    this.equalizerService,
    this.settingsService,
    this.cacheService,
    this.audioHandler,
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer() {
    _initAudioService();
    _initAudioContext();
    _initStreams();
    _initEqualizerHooks();
    _initSettings();
  }

  void _initAudioService() {
    if (audioHandler != null) {
      audioHandler!.onPlayCallback = resume;
      audioHandler!.onPauseCallback = pause;
      audioHandler!.onSkipToNextCallback = playNext;
      audioHandler!.onSkipToPreviousCallback = playPrevious;
      audioHandler!.onSeekCallback = seek;
      audioHandler!.onStopCallback = stop;
    }
    if (kIsWeb) {
      WebMediaSessionHelper.setActionHandlers(
        onPlay: resume,
        onPause: pause,
        onNext: playNext,
        onPrevious: playPrevious,
        onSeek: seek,
      );
    }
  }

  void _initAudioContext() {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _player.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ));
      } catch (e) {
        debugPrint('[AudioPlayerController] setAudioContext error: $e');
      }
    }
  }

  void _syncAudioServiceState() {
    audioHandler?.updatePlaybackState(
      isPlaying: _isPlaying,
      isBuffering: _isBuffering,
      position: _position,
      duration: _duration,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  void _initSettings() {
    if (settingsService != null) {
      _baseVolume = settingsService!.volume;
      _isMuted = settingsService!.isMuted;
      _applyEffectiveVolume();
    }
  }

  void _initEqualizerHooks() {
    if (equalizerService == null) return;
    equalizerService!.onPlaybackRateChanged = (rate) {
      _player.setPlaybackRate(rate);
    };
    equalizerService!.onBalanceChanged = (bal) {
      _player.setBalance(bal);
    };
    equalizerService!.onVolumeMultiplierChanged = (multiplier) {
      _applyEffectiveVolume();
    };
  }

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get errorMessage => _errorMessage;
  double get volume => _isMuted ? 0.0 : _baseVolume;
  double get rawVolume => _baseVolume;
  bool get isMuted => _isMuted;

  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get isShuffle => _isShuffle;
  bool get hasNext =>
      _queue.isNotEmpty &&
      (_repeatMode != PlaybackRepeatMode.off || _currentIndex < _queue.length - 1);
  bool get hasPrevious =>
      _queue.isNotEmpty &&
      (_currentIndex > 0 || _repeatMode == PlaybackRepeatMode.all || _position.inSeconds > 3);

  bool get isSleepTimerActive => _sleepTimer != null || _sleepAtEndOfTrack;
  bool get sleepAtEndOfTrack => _sleepAtEndOfTrack;
  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndTime == null) return null;
    final diff = _sleepTimerEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepTimerEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, _triggerSleepFadeOutAndPause);
    notifyListeners();
  }

  void setSleepAtEndOfTrack(bool value) {
    cancelSleepTimer();
    _sleepAtEndOfTrack = value;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _cancelSleepTimerInternal();
    notifyListeners();
  }

  void _cancelSleepTimerInternal() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    _sleepAtEndOfTrack = false;
  }

  Future<void> _triggerSleepFadeOutAndPause() async {
    _cancelSleepTimerInternal();
    final originalVol = _baseVolume;
    for (int i = 10; i >= 0; i--) {
      final stepVol = (originalVol * (i / 10.0)).clamp(0.0, 1.0);
      await _player.setVolume(stepVol);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await pause();
    await _applyEffectiveVolume();
    notifyListeners();
  }

  void _initStreams() {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      final wasBuffering = _isBuffering;
      final wasPlaying = _isPlaying;

      _isPlaying = state == PlayerState.playing;
      _isBuffering = false;

      if (state == PlayerState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        _syncAudioServiceState();
        _onTrackCompleted();
      }

      if (wasBuffering != _isBuffering || wasPlaying != _isPlaying) {
        _syncAudioServiceState();
        notifyListeners();
      }
    }, onError: (err) {
      debugPrint('[AudioPlayerController] PlayerState stream error: $err');
      _errorMessage = 'Ошибка аудио: $err';
      _isPlaying = false;
      _isBuffering = false;
      _syncAudioServiceState();
      notifyListeners();

      _consecutiveErrors++;
      if (_consecutiveErrors < _queue.length && _queue.isNotEmpty) {
        debugPrint('[AudioPlayerController] Runtime stream error, skipping to next track...');
        Future.microtask(() => playNext(isAutoSkipOnError: true));
      }
    });

    DateTime lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
    _positionSubscription = _player.onPositionChanged.listen((pos) {
      _position = pos;
      _syncAudioServiceState();
      final now = DateTime.now();
      if (now.difference(lastPositionNotify).inMilliseconds >= 250) {
        lastPositionNotify = now;
        notifyListeners();
      }
    }, onError: (err) {
      debugPrint('[AudioPlayerController] Position stream error: $err');
    });

    _durationSubscription = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _syncAudioServiceState();
      notifyListeners();
    }, onError: (err) {
      debugPrint('[AudioPlayerController] Duration stream error: $err');
    });
  }

  void _onTrackCompleted() {
    if (_sleepAtEndOfTrack) {
      _sleepAtEndOfTrack = false;
      _cancelSleepTimerInternal();
      stop();
      return;
    }

    if (_repeatMode == PlaybackRepeatMode.one) {
      if (_currentTrack != null) {
        _executePlay(_currentTrack!);
      }
    } else {
      if (settingsService?.autoPlayNext == false) {
        _isPlaying = false;
        notifyListeners();
        return;
      }
      playNext();
    }
  }

  Future<void> playTrack(Track track, {List<Track>? playlist}) async {
    _errorMessage = null;

    if (playlist != null && playlist.isNotEmpty) {
      _queue.clear();
      _queue.addAll(playlist);
      _currentIndex = _queue.indexWhere((t) => t.id == track.id && t.providerId == track.providerId);
      if (_currentIndex == -1) {
        _queue.insert(0, track);
        _currentIndex = 0;
      }
    } else {
      final existingIndex = _queue.indexWhere((t) => t.id == track.id && t.providerId == track.providerId);
      if (existingIndex != -1) {
        _currentIndex = existingIndex;
      } else {
        _queue.add(track);
        _currentIndex = _queue.length - 1;
      }
    }

    // Если этот же трек уже загружен, просто переключаем play/pause
    if (_currentTrack?.id == track.id && _currentTrack?.providerId == track.providerId) {
      togglePlayPause();
      return;
    }

    await _executePlay(track);
  }

  Future<void> _executePlay(Track track) async {
    _currentTrack = track;
    _position = Duration.zero;
    _duration = track.duration;
    _isBuffering = true;
    audioHandler?.updateTrack(track);
    if (kIsWeb) {
      WebMediaSessionHelper.updateMetadata(track);
    }
    _syncAudioServiceState();
    notifyListeners();

    try {
      // 1. Check if track is cached in AudioCacheService for instant offline playback
      final cachedFile = cacheService?.getCachedFile(track);
      if (cachedFile != null) {
        debugPrint('[AudioPlayerController] Playing from audio cache: ${cachedFile.path}');
        await _player.play(DeviceFileSource(cachedFile.path));
      } else if (!kIsWeb && track.sourceUrl.isNotEmpty && File(track.sourceUrl).existsSync()) {
        debugPrint('[AudioPlayerController] Playing from local file: ${track.sourceUrl}');
        await _player.play(DeviceFileSource(track.sourceUrl));
      } else {
        final provider = registry.activeProviders.firstWhere(
          (p) => p.providerId == track.providerId,
          orElse: () => throw Exception('Provider ${track.providerId} not found'),
        );

        final streamUrl = await provider.getStreamUrl(track);
        final effectiveUrl = WebProxyHelper.proxyStreamUrl(streamUrl);

        if (effectiveUrl.startsWith('http://') || effectiveUrl.startsWith('https://')) {
          await _player.play(UrlSource(effectiveUrl));
          // Transparently cache streaming audio in background after initial playback buffer is established (3.5s delay)
          // Avoids network bandwidth contention during critical initial track start
          if (!kIsWeb && settingsService?.autoCacheAudio != false && cacheService != null) {
            final trackId = track.id;
            Future.delayed(const Duration(milliseconds: 3500), () {
              if (_currentTrack?.id == trackId && _isPlaying) {
                cacheService!.cacheTrackInBackground(track, streamUrl);
              }
            });
          }
        } else {
          await _player.play(DeviceFileSource(effectiveUrl));
          if (!kIsWeb && settingsService?.autoCacheAudio != false && cacheService != null) {
            cacheService!.registerExistingLocalFile(track, effectiveUrl);
          }
        }
      }

      if (equalizerService != null) {
        if (equalizerService!.playbackRate != 1.0) {
          await _player.setPlaybackRate(equalizerService!.playbackRate);
        }
        if (equalizerService!.balance != 0.0) {
          await _player.setBalance(equalizerService!.balance);
        }
      }
      await _applyEffectiveVolume();
      _consecutiveErrors = 0;
      _preloadNextTrackIfNeeded();
    } catch (e) {
      debugPrint('[AudioPlayerController] Error playing "${track.title}": $e');
      _errorMessage = 'Не удалось загрузить "${track.title}"';
      _isBuffering = false;
      _isPlaying = false;
      _syncAudioServiceState();
      notifyListeners();

      _consecutiveErrors++;
      if (_consecutiveErrors < _queue.length && _queue.isNotEmpty) {
        debugPrint('[AudioPlayerController] Auto-skipping to next track (attempt $_consecutiveErrors of ${_queue.length})...');
        Future.delayed(const Duration(milliseconds: 300), () {
          playNext(isAutoSkipOnError: true);
        });
      } else {
        _errorMessage = 'Не удалось воспроизвести треки ($e)';
        _consecutiveErrors = 0;
        notifyListeners();
      }
    }
  }

  void _preloadNextTrackIfNeeded() {
    if (_queue.isEmpty) return;
    int nextIdx = -1;
    if (_currentIndex + 1 < _queue.length) {
      nextIdx = _currentIndex + 1;
    } else if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) {
      nextIdx = 0;
    }

    if (nextIdx >= 0 && nextIdx < _queue.length) {
      final nextTrack = _queue[nextIdx];
      if (nextTrack.providerId == 'youtube') {
        try {
          final yt = registry.allProviders.whereType<YouTubeProvider>().firstOrNull;
          yt?.preloadTrack(nextTrack);
        } catch (_) {}
      }

      // Pre-cache next track in background for gapless offline transition
      if (settingsService?.autoCacheAudio != false && cacheService != null) {
        if (!cacheService!.isCached(nextTrack)) {
          final provider = registry.allProviders.where((p) => p.providerId == nextTrack.providerId).firstOrNull;
          if (provider != null) {
            cacheService!.preloadTrack(nextTrack, provider);
          }
        }
      }
    }
  }

  Future<void> playNext({bool isAutoSkipOnError = false}) async {
    if (!isAutoSkipOnError) {
      _consecutiveErrors = 0;
    }
    if (_queue.isEmpty) return;

    if (_isShuffle && _queue.length > 1) {
      final random = DateTime.now().microsecondsSinceEpoch;
      int nextIdx = random % _queue.length;
      if (nextIdx == _currentIndex) {
        nextIdx = (nextIdx + 1) % _queue.length;
      }
      _currentIndex = nextIdx;
      await _executePlay(_queue[_currentIndex]);
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await _executePlay(_queue[_currentIndex]);
    } else if (_repeatMode == PlaybackRepeatMode.all) {
      _currentIndex = 0;
      await _executePlay(_queue[0]);
    } else {
      await stop();
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;

    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _executePlay(_queue[_currentIndex]);
    } else if (_repeatMode == PlaybackRepeatMode.all) {
      _currentIndex = _queue.length - 1;
      await _executePlay(_queue[_currentIndex]);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final track = _queue[_currentIndex];
    if (_currentTrack?.id == track.id && _currentTrack?.providerId == track.providerId) {
      if (!_isPlaying) {
        await togglePlayPause();
      }
      return;
    }
    await _executePlay(track);
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final isRemovingCurrent = (index == _currentIndex);
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentIndex = -1;
      await stop();
      return;
    }

    if (isRemovingCurrent) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = 0;
      }
      await _executePlay(_queue[_currentIndex]);
    } else if (index < _currentIndex) {
      _currentIndex--;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;

    final current = _currentIndex >= 0 && _currentIndex < _queue.length
        ? _queue[_currentIndex]
        : null;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);

    if (current != null) {
      _currentIndex = _queue.indexOf(current);
    }
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _queue.clear();
    _currentIndex = -1;
    await stop();
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case PlaybackRepeatMode.off:
        _repeatMode = PlaybackRepeatMode.all;
        break;
      case PlaybackRepeatMode.all:
        _repeatMode = PlaybackRepeatMode.one;
        break;
      case PlaybackRepeatMode.one:
        _repeatMode = PlaybackRepeatMode.off;
        break;
    }
    notifyListeners();
  }

  void setRepeatMode(PlaybackRepeatMode mode) {
    _repeatMode = mode;
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    await _player.setPlaybackRate(rate);
  }

  Future<void> setBalance(double balance) async {
    await _player.setBalance(balance);
  }

  Future<void> _applyEffectiveVolume() async {
    if (_isMuted) {
      await _player.setVolume(0.0);
      return;
    }
    final multiplier = (equalizerService?.isEnabled == true && equalizerService?.preampDb != 0.0)
        ? (1.0 + (equalizerService!.preampDb / 12.0) * 0.5).clamp(0.1, 1.5)
        : 1.0;
    await _player.setVolume((_baseVolume * multiplier).clamp(0.0, 1.5));
  }

  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0);
    if (_baseVolume > 0 && _isMuted) {
      _isMuted = false;
      settingsService?.setMuted(false);
    }
    await _applyEffectiveVolume();
    settingsService?.setVolume(_baseVolume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _applyEffectiveVolume();
    settingsService?.toggleMute();
    notifyListeners();
  }

  Future<void> pause() async {
    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
      _syncAudioServiceState();
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (!_isPlaying && _currentTrack != null) {
      await _player.resume();
      _isPlaying = true;
      _syncAudioServiceState();
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) return;

    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    _syncAudioServiceState();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isBuffering = false;
    _consecutiveErrors = 0;
    _syncAudioServiceState();
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
