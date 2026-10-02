import 'dart:io';
import 'package:flutter/material.dart';
import '../../domain/models/track.dart';
import '../providers/youtube_provider.dart';
import '../providers/provider_registry.dart';
import '../../presentation/controllers/audio_player_controller.dart';

class VideoLauncherService {
  final ProviderRegistry? _registry;

  VideoLauncherService([this._registry]);

  static bool? _vlcAvailable;
  static bool? _ffplayAvailable;

  static Future<bool> isVlcAvailable() async {
    if (_vlcAvailable != null) return _vlcAvailable!;
    try {
      final res = await Process.run('which', ['vlc']);
      _vlcAvailable = res.exitCode == 0;
    } catch (_) {
      _vlcAvailable = false;
    }
    return _vlcAvailable!;
  }

  static Future<bool> isFfplayAvailable() async {
    if (_ffplayAvailable != null) return _ffplayAvailable!;
    try {
      final res = await Process.run('which', ['ffplay']);
      _ffplayAvailable = res.exitCode == 0;
    } catch (_) {
      _ffplayAvailable = false;
    }
    return _ffplayAvailable!;
  }

  YouTubeProvider? _findYouTubeProvider() {
    if (_registry != null) {
      final match = _registry.allProviders.whereType<YouTubeProvider>();
      if (match.isNotEmpty) return match.first;
    }
    return null;
  }

  /// Pauses music audio playback and launches the video stream or browser.
  Future<void> openVideo(
    Track track, {
    AudioPlayerController? audioController,
    BuildContext? context,
  }) async {
    // 1. Pause current audio to avoid audio overlap
    if (audioController != null && audioController.isPlaying) {
      await audioController.pause();
    }

    final webUrl = track.sourceUrl.isNotEmpty
        ? track.sourceUrl
        : 'https://www.youtube.com/watch?v=${track.id}';

    String? videoStreamUrl;
    final ytProvider = _findYouTubeProvider() ?? YouTubeProvider();
    try {
      videoStreamUrl = await ytProvider.getVideoStreamUrl(track);
    } catch (e) {
      debugPrint('Could not retrieve direct video stream for ${track.id}: $e');
    }

    final hasVlc = await isVlcAvailable();
    final hasFfplay = await isFfplayAvailable();

    bool launched = false;

    if (Platform.isLinux) {
      if (videoStreamUrl != null && hasVlc) {
        try {
          await Process.start('vlc', ['--play-and-exit', videoStreamUrl]);
          launched = true;
          _showNotice(
            context,
            'Видео запущено в VLC: ${track.title}',
            webUrl: webUrl,
          );
        } catch (_) {}
      } else if (videoStreamUrl != null && hasFfplay) {
        try {
          await Process.start('ffplay', [
            '-window_title',
            '${track.title} - ${track.artist}',
            videoStreamUrl,
          ]);
          launched = true;
          _showNotice(
            context,
            'Видео запущено в ffplay: ${track.title}',
            webUrl: webUrl,
          );
        } catch (_) {}
      }

      if (!launched) {
        try {
          await Process.start('xdg-open', [webUrl]);
          launched = true;
          _showNotice(
            context,
            'Открываем видео в браузере: ${track.title}',
          );
        } catch (_) {}
      }
    } else {
      // Non-linux fallback (e.g. mobile/web/macos/windows)
      try {
        if (Platform.isWindows) {
          await Process.start('cmd', ['/c', 'start', webUrl]);
        } else if (Platform.isMacOS) {
          await Process.start('open', [webUrl]);
        }
        launched = true;
      } catch (_) {}
    }

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось запустить видео: $webUrl'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showNotice(BuildContext? context, String message, {String? webUrl}) {
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.smart_display, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: webUrl != null
            ? SnackBarAction(
                label: 'В браузере',
                textColor: Colors.amberAccent,
                onPressed: () {
                  try {
                    Process.start('xdg-open', [webUrl]);
                  } catch (_) {}
                },
              )
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
