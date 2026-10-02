import 'dart:async';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';

class FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _controllers = {};

  @override
  Future<void> create(String playerId) {
    _controllers.putIfAbsent(playerId, () => StreamController<AudioEvent>.broadcast(sync: true));
    return Future.value();
  }

  @override
  Future<void> dispose(String playerId) {
    _controllers[playerId]?.close();
    _controllers.remove(playerId);
    return Future.value();
  }

  @override
  Future<void> emitError(String playerId, String code, String message) => Future.value();

  @override
  Future<void> emitLog(String playerId, String message) => Future.value();

  @override
  Future<int?> getCurrentPosition(String playerId) => Future.value(0);

  @override
  Future<int?> getDuration(String playerId) => Future.value(0);

  @override
  Future<void> pause(String playerId) => Future.value();

  @override
  Future<void> release(String playerId) => Future.value();

  @override
  Future<void> resume(String playerId) => Future.value();

  @override
  Future<void> seek(String playerId, Duration position) => Future.value();

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) => Future.value();

  @override
  Future<void> setBalance(String playerId, double balance) => Future.value();

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) => Future.value();

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) => Future.value();

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) => Future.value();

  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes, {String? mimeType}) {
    _controllers[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    return Future.value();
  }

  @override
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) {
    _controllers[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    return Future.value();
  }

  @override
  Future<void> setVolume(String playerId, double volume) => Future.value();

  @override
  Future<void> stop(String playerId) => Future.value();

  @override
  Stream<AudioEvent> getEventStream(String playerId) {
    return _controllers.putIfAbsent(playerId, () => StreamController<AudioEvent>.broadcast(sync: true)).stream;
  }
}

class FakeGlobalAudioplayersPlatform extends GlobalAudioplayersPlatformInterface {
  final StreamController<GlobalAudioEvent> _controller = StreamController<GlobalAudioEvent>.broadcast(sync: true);

  @override
  Future<void> init() => Future.value();

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) => Future.value();

  @override
  Future<void> emitGlobalLog(String message) => Future.value();

  @override
  Future<void> emitGlobalError(String code, String message) => Future.value();

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _controller.stream;
}

class FakeAudioPlayer extends AudioPlayer {
  final StreamController<PlayerState> _stateController = StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _posController = StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration> _durController = StreamController<Duration>.broadcast(sync: true);

  FakeAudioPlayer() {
    positionUpdater = null;
  }

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<Duration> get onPositionChanged => _posController.stream;

  @override
  Stream<Duration> get onDurationChanged => _durController.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState.playing);
    }
    return Future.value();
  }

  @override
  Future<void> stop() {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState.stopped);
    }
    return Future.value();
  }

  @override
  Future<void> pause() {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState.paused);
    }
    return Future.value();
  }

  @override
  Future<void> resume() {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState.playing);
    }
    return Future.value();
  }

  @override
  Future<void> seek(Duration position) {
    if (!_posController.isClosed) {
      _posController.add(position);
    }
    return Future.value();
  }

  @override
  Future<void> setPlaybackRate(double playbackRate) => Future.value();

  @override
  Future<void> setBalance(double balance) => Future.value();

  @override
  Future<void> setVolume(double volume) => Future.value();

  @override
  Future<void> dispose() async {
    if (!_stateController.isClosed) await _stateController.close();
    if (!_posController.isClosed) await _posController.close();
    if (!_durController.isClosed) await _durController.close();
  }
}
