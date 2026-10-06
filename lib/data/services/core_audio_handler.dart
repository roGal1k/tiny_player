import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../../domain/models/track.dart';

class CoreAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onSkipToNextCallback;
  Future<void> Function()? onSkipToPreviousCallback;
  Future<void> Function(Duration)? onSeekCallback;
  Future<void> Function()? onStopCallback;

  CoreAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  static Future<CoreAudioHandler?> initHandler() async {
    // AudioService is primarily intended for mobile (Android/iOS) and Web
    if (!kIsWeb && !(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    try {
      return await AudioService.init(
        builder: () => CoreAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.gera.player.channel.audio',
          androidNotificationChannelName: 'CorePlayer Playback',
          androidNotificationChannelDescription: 'Active audio playback controls',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (e) {
      debugPrint('[CoreAudioHandler] AudioService.init error: $e');
      return null;
    }
  }

  void updateTrack(Track track) {
    mediaItem.add(
      MediaItem(
        id: track.id,
        album: track.album ?? 'CorePlayer',
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        artUri: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
            ? Uri.tryParse(track.artworkUrl!)
            : null,
      ),
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required bool isBuffering,
    required Duration position,
    required Duration duration,
    bool hasNext = true,
    bool hasPrevious = true,
  }) {
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: controls.length >= 3
            ? const [0, 1, 2]
            : List.generate(controls.length, (i) => i),
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : (isPlaying ? AudioProcessingState.ready : AudioProcessingState.idle),
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (onPlayCallback != null) {
      await onPlayCallback!();
    }
  }

  @override
  Future<void> pause() async {
    if (onPauseCallback != null) {
      await onPauseCallback!();
    }
  }

  @override
  Future<void> stop() async {
    if (onStopCallback != null) {
      await onStopCallback!();
    }
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeekCallback != null) {
      await onSeekCallback!(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (onSkipToNextCallback != null) {
      await onSkipToNextCallback!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipToPreviousCallback != null) {
      await onSkipToPreviousCallback!();
    }
  }
}
