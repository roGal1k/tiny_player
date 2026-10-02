import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../domain/models/track.dart';
import '../../data/providers/provider_registry.dart';
import '../../data/providers/youtube_provider.dart';
import '../../data/services/equalizer_service.dart';
import '../../data/services/settings_service.dart';

enum PlaybackRepeatMode {
  off,
  all,
  one,
}

class AudioPlayerController extends ChangeNotifier {
  final ProviderRegistry registry;
  final EqualizerService? equalizerService;
  final SettingsService? settingsService;
  final AudioPlayer _player;

  Track? _currentTrack;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  double _baseVolume = 1.0;
  bool _isMuted = false;

  // Queue / Playlist state
  final List<Track> _queue = [];
  int _currentIndex = -1;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;
  bool _isShuffle = false;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  AudioPlayerController({
    required this.registry,
    this.equalizerService,
    this.settingsService,
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer() {
    _initStreams();
    _initEqualizerHooks();
    _initSettings();
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

  void _initStreams() {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      final wasBuffering = _isBuffering;
      final wasPlaying = _isPlaying;

      _isPlaying = state == PlayerState.playing;
      _isBuffering = false;

      if (state == PlayerState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        _onTrackCompleted();
      }

      if (wasBuffering != _isBuffering || wasPlaying != _isPlaying) {
        notifyListeners();
      }
    });

    _positionSubscription = _player.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durationSubscription = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
  }

  void _onTrackCompleted() {
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
    notifyListeners();

    try {
      final provider = registry.activeProviders.firstWhere(
        (p) => p.providerId == track.providerId,
        orElse: () => throw Exception('Provider ${track.providerId} not found'),
      );

      final streamUrl = await provider.getStreamUrl(track);

      await _player.stop();
      if (streamUrl.startsWith('http://') || streamUrl.startsWith('https://')) {
        await _player.play(UrlSource(streamUrl));
      } else {
        await _player.play(DeviceFileSource(streamUrl));
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
      _preloadNextTrackIfNeeded();
    } catch (e) {
      _errorMessage = e.toString();
      _isBuffering = false;
      _isPlaying = false;
      notifyListeners();
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
    }
  }

  Future<void> playNext() async {
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
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isBuffering = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
