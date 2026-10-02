import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/track.dart';
import '../controllers/audio_player_controller.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/video_launcher_service.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const QueueScreen(),
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
      default:
        return Colors.deepPurpleAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioController = context.watch<AudioPlayerController>();
    final downloadManager = Provider.of<DownloadManager?>(context);
    final queue = audioController.queue;
    final currentIndex = audioController.currentIndex;

    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.75;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF161922),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.queue_music,
                    color: Colors.cyanAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ТРЕКЛИСТ & ОЧЕРЕДЬ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        queue.isEmpty
                            ? 'Очередь пуста'
                            : 'Трек ${currentIndex >= 0 ? currentIndex + 1 : 0} из ${queue.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),

                // Shuffle button
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: audioController.isShuffle
                        ? Colors.amberAccent
                        : Colors.white38,
                    size: 22,
                  ),
                  tooltip: audioController.isShuffle
                      ? 'Случайный порядок: ВКЛ'
                      : 'Случайный порядок: ВЫКЛ',
                  onPressed: audioController.toggleShuffle,
                ),

                // Repeat Mode button
                IconButton(
                  icon: Icon(
                    audioController.repeatMode == PlaybackRepeatMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: audioController.repeatMode == PlaybackRepeatMode.off
                        ? Colors.white38
                        : (audioController.repeatMode == PlaybackRepeatMode.one
                            ? Colors.purpleAccent
                            : Colors.cyanAccent),
                    size: 22,
                  ),
                  tooltip: () {
                    switch (audioController.repeatMode) {
                      case PlaybackRepeatMode.off:
                        return 'Повтор: ВЫКЛ';
                      case PlaybackRepeatMode.all:
                        return 'Повтор: Все треки';
                      case PlaybackRepeatMode.one:
                        return 'Повтор: Один трек';
                    }
                  }(),
                  onPressed: audioController.toggleRepeatMode,
                ),

                // Clear queue button
                if (queue.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                    tooltip: 'Очистить очередь',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E222D),
                          title: const Text('Очистить очередь?'),
                          content: const Text(
                            'Все треки будут удалены из текущего плейлиста, а воспроизведение будет остановлено.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                audioController.clearQueue();
                              },
                              child: const Text('Очистить'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white12),

          // Queue List or Empty State
          Expanded(
            child: queue.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.queue_music,
                          size: 56,
                          color: Colors.white24,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Очередь воспроизведения пуста',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Запустите трек из поиска или библиотеки',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: queue.length,
                    onReorder: audioController.reorderQueue,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;
                      final providerColor = _getProviderColor(track.providerId);

                      return Container(
                        key: ValueKey('${track.providerId}_${track.id}_$index'),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent
                                ? providerColor.withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.05),
                            width: isCurrent ? 1.2 : 0.8,
                          ),
                        ),
                        child: Material(
                          color: isCurrent
                              ? providerColor.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Drag handle
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 8.0),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: Colors.white30,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                // Current playing indicator or track index
                                SizedBox(
                                  width: 28,
                                  child: Center(
                                    child: isCurrent
                                        ? Icon(
                                            audioController.isPlaying
                                                ? Icons.volume_up
                                                : Icons.pause,
                                            color: providerColor,
                                            size: 20,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Artwork thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: track.artworkUrl != null &&
                                          track.artworkUrl!.isNotEmpty
                                      ? Image.network(
                                          track.artworkUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) =>
                                              Container(
                                            width: 40,
                                            height: 40,
                                            color: Colors.white12,
                                            child: const Icon(
                                              Icons.music_note,
                                              color: Colors.white38,
                                              size: 20,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: 40,
                                          height: 40,
                                          color: Colors.white12,
                                          child: const Icon(
                                            Icons.music_note,
                                            color: Colors.white38,
                                            size: 20,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isCurrent ? providerColor : Colors.white,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: providerColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    track.providerId.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: providerColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDuration(track.duration),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Download button if downloadable
                                if (track.isDownloadable && downloadManager != null)
                                  Builder(
                                    builder: (ctx) {
                                      final taskKey =
                                          '${track.providerId}_${track.id}';
                                      final task =
                                          downloadManager.getTask(taskKey);

                                      if (task?.status ==
                                          DownloadStatus.downloading) {
                                        return SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: Padding(
                                            padding: const EdgeInsets.all(6.0),
                                            child: CircularProgressIndicator(
                                              value: task!.progress > 0
                                                  ? task.progress
                                                  : null,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      }

                                      if (task?.status ==
                                          DownloadStatus.completed) {
                                        return const Icon(
                                          Icons.check_circle,
                                          color: Colors.greenAccent,
                                          size: 20,
                                        );
                                      }

                                      return IconButton(
                                        iconSize: 20,
                                        icon: const Icon(
                                          Icons.download_rounded,
                                          color: Colors.white70,
                                        ),
                                        tooltip: 'Скачать трек в библиотеку',
                                        onPressed: () {
                                          downloadManager.downloadTrack(track);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Начато скачивание: ${track.title}',
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),

                                // Watch Video button for YouTube tracks
                                if (track.providerId == 'youtube')
                                  IconButton(
                                    iconSize: 20,
                                    icon: const Icon(
                                      Icons.smart_display_outlined,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Смотреть видео / клип',
                                    onPressed: () {
                                      final launcher = VideoLauncherService(audioController.registry);
                                      launcher.openVideo(track, audioController: audioController, context: context);
                                    },
                                  ),

                                // Remove / Skip button
                                IconButton(
                                  iconSize: 20,
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white54,
                                  ),
                                  tooltip: 'Удалить из очереди',
                                  onPressed: () {
                                    audioController.removeFromQueue(index);
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              audioController.playQueueIndex(index);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
