import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/audio_player_controller.dart';
import '../../data/services/genius_lyrics_service.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/equalizer_service.dart';
import '../screens/equalizer_screen.dart';
import '../screens/queue_screen.dart';
import '../../domain/models/track.dart';
import '../../data/services/video_launcher_service.dart';
import '../../data/services/local_library_service.dart';
import 'now_playing_sheet.dart';

class MiniPlayerWidget extends StatelessWidget {
  const MiniPlayerWidget({super.key});

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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AudioPlayerController>();
    final track = controller.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width <= 680;
    final currentPos = controller.position;
    final totalDuration = controller.duration.inMilliseconds > 0 
        ? controller.duration 
        : track.duration;

    final progress = totalDuration.inMilliseconds > 0
        ? (currentPos.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Улучшенный прогресс-бар сверху мини-плеера (увеличенная зона касания и полоса 6px)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && totalDuration.inMilliseconds > 0) {
                final localX = details.localPosition.dx;
                final ratio = (localX / box.size.width).clamp(0.0, 1.0);
                controller.seek(Duration(milliseconds: (ratio * totalDuration.inMilliseconds).toInt()));
              }
            },
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && totalDuration.inMilliseconds > 0) {
                final localX = details.localPosition.dx;
                final ratio = (localX / box.size.width).clamp(0.0, 1.0);
                controller.seek(Duration(milliseconds: (ratio * totalDuration.inMilliseconds).toInt()));
              }
            },
            child: Container(
              height: 14,
              alignment: Alignment.center,
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getProviderColor(track.providerId),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (controller.errorMessage != null)
            Container(
              color: Colors.red.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      controller.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: () => NowPlayingSheet.show(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
              children: [
                // Обложка трека
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.0),
                  child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                      ? Image.network(
                          track.artworkUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            width: 48,
                            height: 48,
                            color: Colors.white12,
                            child: const Icon(Icons.music_note, color: Colors.white70),
                          ),
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          color: Colors.white12,
                          child: const Icon(Icons.music_note, color: Colors.white70),
                        ),
                ),
                const SizedBox(width: 12),

                // Название, артист и источник
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getProviderColor(track.providerId).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getProviderColor(track.providerId).withValues(alpha: 0.6),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              track.providerId.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _getProviderColor(track.providerId),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_formatDuration(currentPos)} / ${_formatDuration(totalDuration)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()],
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Избранное ❤️
                Builder(
                  builder: (ctx) {
                    final libService = Provider.of<LocalLibraryService?>(ctx);
                    if (libService == null) return const SizedBox.shrink();
                    final isFav = libService.isFavorite(track.id);
                    return IconButton(
                      iconSize: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.redAccent : Colors.white60,
                      ),
                      tooltip: isFav ? 'В избранном' : 'В избранное',
                      onPressed: () => libService.toggleFavorite(track),
                    );
                  },
                ),
                const SizedBox(width: 6),

                if (isMobile) ...[
                  // Лаконичные мобильные контролы (без переполнения экрана)
                  if (controller.isBuffering)
                    const SizedBox(
                      width: 38,
                      height: 38,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  else
                    IconButton(
                      iconSize: 36,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        controller.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: _getProviderColor(track.providerId),
                      ),
                      tooltip: controller.isPlaying ? 'Пауза' : 'Воспроизведение',
                      onPressed: controller.togglePlayPause,
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    tooltip: 'Следующий трек',
                    onPressed: controller.playNext,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    iconSize: 26,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
                    tooltip: 'Развернуть плеер',
                    onPressed: () => NowPlayingSheet.show(context),
                  ),
                ] else ...[
                  // Полный набор контролов для десктопа и планшета
                  if (controller.isBuffering)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.all(10.0),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  else
                    IconButton(
                      iconSize: 34,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        controller.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: _getProviderColor(track.providerId),
                      ),
                      onPressed: controller.togglePlayPause,
                    ),

                  const SizedBox(width: 4),

                  // Кнопка просмотра видео (YouTube)
                  if (track.providerId == 'youtube')
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.smart_display_outlined, color: Colors.redAccent),
                      tooltip: 'Смотреть видео / клип',
                      onPressed: () {
                        final launcher = VideoLauncherService(controller.registry);
                        launcher.openVideo(track, audioController: controller, context: context);
                      },
                    ),

                  // Кнопка текстов песен (Genius)
                  IconButton(
                    iconSize: 22,
                    icon: const Icon(Icons.lyrics_outlined, color: Colors.white70),
                    tooltip: 'Song lyrics (Genius)',
                    onPressed: () => _showLyricsModal(context, track),
                  ),

                  // Кнопка Эквалайзера & Тюнера (AIMP Style)
                  Builder(
                    builder: (ctx) {
                      final eq = Provider.of<EqualizerService?>(ctx);
                      final isEqOn = eq?.isEnabled ?? false;
                      return IconButton(
                        iconSize: 22,
                        icon: Icon(
                          Icons.tune,
                          color: isEqOn ? Colors.tealAccent : Colors.white70,
                        ),
                        tooltip: 'Эквалайзер & Тюнер (AIMP)',
                        onPressed: () => EqualizerScreen.showAsBottomSheet(context),
                      );
                    },
                  ),

                  // Кнопка Очереди воспроизведения (Треклист)
                  IconButton(
                    iconSize: 22,
                    icon: Icon(
                      Icons.queue_music,
                      color: controller.queue.isNotEmpty ? Colors.cyanAccent : Colors.white70,
                    ),
                    tooltip: 'Очередь воспроизведения (${controller.queue.length})',
                    onPressed: () => QueueScreen.showAsBottomSheet(context),
                  ),

                  // Регулятор громкости
                  Builder(
                    builder: (ctx) {
                      final isWideScreen = MediaQuery.of(ctx).size.width > 680;
                      final isMuted = controller.isMuted || controller.volume == 0;
                      final volIcon = isMuted
                          ? Icons.volume_off
                          : (controller.volume < 0.5 ? Icons.volume_down : Icons.volume_up);

                      if (isWideScreen) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              iconSize: 22,
                              icon: Icon(
                                volIcon,
                                color: isMuted ? Colors.redAccent : Colors.white70,
                              ),
                              tooltip: isMuted ? 'Включить звук' : 'Выключить звук',
                              onPressed: controller.toggleMute,
                            ),
                            SizedBox(
                              width: 75,
                              child: SliderTheme(
                                data: SliderTheme.of(ctx).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  activeTrackColor: theme.colorScheme.primary,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: theme.colorScheme.primary,
                                ),
                                child: Slider(
                                  value: controller.volume,
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (val) => controller.setVolume(val),
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return IconButton(
                          iconSize: 22,
                          icon: Icon(
                            volIcon,
                            color: isMuted ? Colors.redAccent : Colors.white70,
                          ),
                          tooltip: 'Громкость (${(controller.volume * 100).toInt()}%)',
                          onPressed: () => _showVolumePopup(ctx, controller),
                        );
                      }
                    },
                  ),

                  // Кнопка скачивания трека в локальную библиотеку
                  Builder(
                    builder: (ctx) {
                      final downloadManager = Provider.of<DownloadManager?>(ctx);
                      if (downloadManager == null || !track.isDownloadable) {
                        return const SizedBox.shrink();
                      }

                      final taskKey = '${track.providerId}_${track.id}';
                      final task = downloadManager.getTask(taskKey);

                      if (task?.status == DownloadStatus.downloading) {
                        return SizedBox(
                          width: 32,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: task!.progress > 0 ? task.progress : null,
                                strokeWidth: 2,
                              ),
                              Text(
                                '${(task.progress * 100).toInt()}%',
                                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }

                      if (task?.status == DownloadStatus.completed) {
                        return IconButton(
                          iconSize: 22,
                          icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                          tooltip: 'Saved to library',
                          onPressed: () {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Saved to: ${task?.savedFilePath}')),
                            );
                          },
                        );
                      }

                      return IconButton(
                        iconSize: 22,
                        icon: const Icon(Icons.download_rounded, color: Colors.white70),
                        tooltip: 'Download track to local library',
                        onPressed: () {
                          downloadManager.downloadTrack(track);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Downloading: ${track.title}')),
                          );
                        },
                      );
                    },
                  ),

                  // Кнопка закрытия
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    tooltip: 'Close player',
                    onPressed: controller.stop,
                  ),
                ],
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }

  void _showLyricsModal(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (sheetCtx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                              ? Image.network(
                                  track.artworkUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 44),
                                )
                              : const Icon(Icons.music_note, size: 44),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                track.artist,
                                style: const TextStyle(fontSize: 13, color: Colors.white60),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                          ),
                          child: const Text(
                            'GENIUS LYRICS',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: FutureBuilder<String?>(
                      future: context.read<GeniusLyricsService>().getLyrics(track.title, track.artist),
                      builder: (fCtx, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text('Searching lyrics on Genius...', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          );
                        }

                        final lyrics = snapshot.data;
                        if (lyrics == null || lyrics.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'Lyrics not found on Genius for this song.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 15),
                              ),
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                          child: Text(
                            lyrics,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.7,
                              letterSpacing: 0.3,
                            ),
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

  void _showVolumePopup(BuildContext context, AudioPlayerController controller) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<AudioPlayerController>(
          builder: (ctx, ctrl, _) {
            final isMuted = ctrl.isMuted || ctrl.volume == 0;
            final theme = Theme.of(ctx);
            return AlertDialog(
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMuted ? Icons.volume_off : Icons.volume_up,
                        color: isMuted ? Colors.redAccent : theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('Громкость', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(
                    '${(ctrl.volume * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              content: Row(
                children: [
                  IconButton(
                    icon: Icon(ctrl.isMuted ? Icons.volume_off : Icons.volume_mute),
                    color: ctrl.isMuted ? Colors.redAccent : Colors.white70,
                    tooltip: ctrl.isMuted ? 'Включить звук' : 'Выключить звук',
                    onPressed: ctrl.toggleMute,
                  ),
                  Expanded(
                    child: Slider(
                      value: ctrl.volume,
                      min: 0.0,
                      max: 1.0,
                      activeColor: theme.colorScheme.primary,
                      inactiveColor: Colors.white12,
                      onChanged: (val) => ctrl.setVolume(val),
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
}

