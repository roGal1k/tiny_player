import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/audio_player_controller.dart';
import '../../domain/models/track.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/video_launcher_service.dart';
import '../screens/equalizer_screen.dart';
import '../screens/queue_screen.dart';
import '../../data/services/genius_lyrics_service.dart';
import '../../data/services/local_library_service.dart';
import 'audio_visualizer_widget.dart';

class NowPlayingSheet extends StatelessWidget {
  const NowPlayingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NowPlayingSheet(),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Color _getProviderColor(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'soundcloud':
        return Colors.orangeAccent;
      case 'jamendo':
        return Colors.redAccent;
      case 'internet_archive':
        return Colors.blueAccent;
      case 'vk':
        return Colors.lightBlueAccent;
      case 'freesound':
        return Colors.tealAccent;
      case 'hitmo':
        return Colors.pinkAccent;
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'audius':
        return const Color(0xFFCC0FE0);
      case 'deezer':
        return const Color(0xFFFEAA2D);
      default:
        return Colors.deepPurpleAccent;
    }
  }

  void _showLyricsModal(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetCtx) {
        final lyricsService = Provider.of<GeniusLyricsService>(context, listen: false);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Текст песни: ${track.title}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: FutureBuilder<String?>(
                      future: lyricsService.getLyrics(track.title, track.artist),
                      builder: (ctx, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'Текст песни не найден',
                                style: TextStyle(color: Colors.white60),
                              ),
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            snapshot.data!,
                            style: const TextStyle(fontSize: 15, height: 1.6),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSleepTimerModal(BuildContext context, AudioPlayerController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetCtx) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bedtime, size: 20, color: Colors.indigoAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Таймер сна',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (controller.isSleepTimerActive) ...[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    controller.sleepAtEndOfTrack
                        ? 'Остановится в конце текущего трека'
                        : 'Осталось: ${_formatDuration(controller.sleepTimerRemaining ?? Duration.zero)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_off, color: Colors.redAccent),
                  title: const Text('Отключить таймер', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    controller.cancelSleepTimer();
                    Navigator.of(bottomSheetCtx).pop();
                  },
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('В конце этого трека'),
                onTap: () {
                  controller.setSleepAtEndOfTrack(true);
                  Navigator.of(bottomSheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Таймер сна: музыка остановится после этого трека'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('15 минут'),
                onTap: () {
                  controller.setSleepTimer(const Duration(minutes: 15));
                  Navigator.of(bottomSheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Таймер сна установлен на 15 минут'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('30 минут'),
                onTap: () {
                  controller.setSleepTimer(const Duration(minutes: 30));
                  Navigator.of(bottomSheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Таймер сна установлен на 30 минут'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('45 минут'),
                onTap: () {
                  controller.setSleepTimer(const Duration(minutes: 45));
                  Navigator.of(bottomSheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Таймер сна установлен на 45 минут'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('60 минут'),
                onTap: () {
                  controller.setSleepTimer(const Duration(minutes: 60));
                  Navigator.of(bottomSheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Таймер сна установлен на 60 минут'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AudioPlayerController>();
    final track = controller.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final providerColor = _getProviderColor(track.providerId);
    final currentPos = controller.position;
    final totalDuration = controller.duration.inMilliseconds > 0
        ? controller.duration
        : track.duration;

    final maxMs = totalDuration.inMilliseconds > 0
        ? totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = currentPos.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Column(
                children: [
                  const Text(
                    'СЕЙЧАС ИГРАЕТ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: providerColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: providerColor.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Text(
                      track.providerId.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: providerColor,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.queue_music, size: 24),
                onPressed: () {
                  Navigator.of(context).pop();
                  QueueScreen.showAsBottomSheet(context);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Album Art
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  boxShadow: [
                    BoxShadow(
                      color: providerColor.withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                    ? Image.network(
                        track.artworkUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.music_note,
                          size: 80,
                          color: providerColor.withValues(alpha: 0.6),
                        ),
                      )
                    : Icon(
                        Icons.music_note,
                        size: 80,
                        color: providerColor.withValues(alpha: 0.6),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Dynamic Audio Visualizer
          AudioVisualizerWidget(
            color: providerColor,
            isPlaying: controller.isPlaying,
            height: 26,
          ),

          const SizedBox(height: 12),

          // Track Info & Favorite button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (ctx) {
                  final libService = Provider.of<LocalLibraryService?>(ctx);
                  if (libService == null) return const SizedBox.shrink();
                  final isFav = libService.isFavorite(track.id);
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.redAccent : Colors.white70,
                      size: 26,
                    ),
                    tooltip: isFav ? 'В избранном' : 'Добавить в избранное',
                    onPressed: () async {
                      final added = await libService.toggleFavorite(track);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added ? 'Добавлено в избранное ❤️' : 'Удалено из избранного',
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Wide Scrubber / Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: providerColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: currentMs,
              min: 0.0,
              max: maxMs,
              onChanged: (val) {
                controller.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(currentPos),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Colors.white60,
                  ),
                ),
                Text(
                  _formatDuration(totalDuration),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Main Controls: Shuffle, Prev, Play/Pause, Next, Repeat
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: controller.isShuffle ? providerColor : Colors.white54,
                ),
                onPressed: controller.toggleShuffle,
              ),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous),
                onPressed: controller.hasPrevious ? controller.playPrevious : null,
              ),
              GestureDetector(
                onTap: controller.togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: providerColor,
                    boxShadow: [
                      BoxShadow(
                        color: providerColor.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: controller.isBuffering
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          controller.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 38,
                          color: Colors.white,
                        ),
                ),
              ),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next),
                onPressed: controller.hasNext ? controller.playNext : null,
              ),
              IconButton(
                icon: Icon(
                  controller.repeatMode == PlaybackRepeatMode.one
                      ? Icons.repeat_one
                      : (controller.repeatMode == PlaybackRepeatMode.all
                          ? Icons.repeat
                          : Icons.repeat),
                  color: controller.repeatMode != PlaybackRepeatMode.off
                      ? providerColor
                      : Colors.white54,
                ),
                onPressed: controller.toggleRepeatMode,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Secondary Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Lyrics
              IconButton(
                icon: const Icon(Icons.lyrics_outlined, color: Colors.white70),
                tooltip: 'Текст песни',
                onPressed: () => _showLyricsModal(context, track),
              ),
              // Sleep Timer
              IconButton(
                icon: Icon(
                  controller.isSleepTimerActive ? Icons.bedtime : Icons.bedtime_outlined,
                  color: controller.isSleepTimerActive ? providerColor : Colors.white70,
                ),
                tooltip: controller.isSleepTimerActive
                    ? 'Таймер сна активен'
                    : 'Таймер сна',
                onPressed: () => _showSleepTimerModal(context, controller),
              ),
              // Equalizer
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white70),
                tooltip: 'Эквалайзер',
                onPressed: () {
                  Navigator.of(context).pop();
                  EqualizerScreen.showAsBottomSheet(context);
                },
              ),
              // Download
              Builder(
                builder: (ctx) {
                  final dl = Provider.of<DownloadManager?>(ctx);
                  if (dl == null || !track.isDownloadable) {
                    return const SizedBox.shrink();
                  }
                  final task = dl.getTask('${track.providerId}_${track.id}');
                  if (task?.status == DownloadStatus.downloading) {
                    return SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: task!.progress > 0 ? task.progress : null,
                        strokeWidth: 2,
                      ),
                    );
                  }
                  return IconButton(
                    icon: Icon(
                      task?.status == DownloadStatus.completed
                          ? Icons.check_circle
                          : Icons.download_outlined,
                      color: task?.status == DownloadStatus.completed
                          ? Colors.greenAccent
                          : Colors.white70,
                    ),
                    tooltip: 'Скачать',
                    onPressed: () {
                      if (task?.status != DownloadStatus.completed) {
                        dl.downloadTrack(track);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Скачивание "${track.title}" начато')),
                        );
                      }
                    },
                  );
                },
              ),
              // YouTube video if applicable
              if (track.providerId == 'youtube')
                IconButton(
                  icon: const Icon(Icons.smart_display_outlined, color: Colors.redAccent),
                  tooltip: 'Смотреть видео',
                  onPressed: () {
                    final launcher = VideoLauncherService(controller.registry);
                    launcher.openVideo(track, audioController: controller, context: context);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
