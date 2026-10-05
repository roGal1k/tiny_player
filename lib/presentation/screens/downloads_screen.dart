import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/local_library_service.dart';
import '../controllers/audio_player_controller.dart';
import '../../domain/models/track.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Color _getProviderColor(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'hitmo':
        return Colors.pinkAccent;
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'audius':
        return const Color(0xFFCC0FE0);
      case 'deezer':
        return const Color(0xFFFEAA2D);
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
      default:
        return Colors.deepPurpleAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadManager = context.watch<DownloadManager>();
    final libraryService = context.watch<LocalLibraryService>();
    final audioController = context.watch<AudioPlayerController>();
    final tasks = downloadManager.tasks;
    final downloadedTracks = libraryService.tracks;
    final activeCount = tasks.where((t) => t.status == DownloadStatus.downloading).length;

    final titleText = downloadedTracks.isNotEmpty
        ? 'Загрузки (${downloadedTracks.length})'
        : (activeCount > 0 ? 'Загрузки ($activeCount)' : 'Загрузки');

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _buildDownloadsTab(context, downloadManager, libraryService, audioController, tasks, downloadedTracks),
    );
  }

  Widget _buildDownloadsTab(
    BuildContext context,
    DownloadManager downloadManager,
    LocalLibraryService libraryService,
    AudioPlayerController audioController,
    List<DownloadTask> tasks,
    List<Track> downloadedTracks,
  ) {
    final activeTasks = tasks.where((t) => t.status == DownloadStatus.downloading).toList();
    final failedTasks = tasks.where((t) => t.status == DownloadStatus.failed).toList();

    if (downloadedTracks.isEmpty && activeTasks.isEmpty && failedTasks.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              const Text(
                'Нет скачанных треков',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Найдите треки со значком загрузки или нажмите «Скачать всё» в результатах поиска — они сохранятся в постоянную библиотеку и будут всегда доступны без интернета.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    int totalDownloadedBytes = 0;
    for (final track in downloadedTracks) {
      if (track.sourceUrl.isNotEmpty) {
        try {
          final f = File(track.sourceUrl);
          if (f.existsSync()) totalDownloadedBytes += f.lengthSync();
        } catch (_) {}
      }
    }

    return Column(
      children: [
        // Информационная панель с кнопками управления
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_special, size: 20, color: Colors.pinkAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${downloadedTracks.length} скачанных треков',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      totalDownloadedBytes > 0
                          ? 'Локальная библиотека • ${_formatBytes(totalDownloadedBytes)}'
                          : 'Локальная библиотека',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              if (downloadedTracks.isNotEmpty) ...[
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Слушать все'),
                  onPressed: () {
                    audioController.playTrack(downloadedTracks.first, playlist: downloadedTracks);
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.shuffle, size: 18),
                  tooltip: 'Случайно',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final shuffled = List<Track>.from(downloadedTracks)..shuffle();
                    audioController.playTrack(shuffled.first, playlist: shuffled);
                  },
                ),
              ],
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Обновить библиотеку',
                visualDensity: VisualDensity.compact,
                onPressed: () => libraryService.loadLibrary(),
              ),
            ],
          ),
        ),

        // Список треков и активных задач
        Expanded(
          child: ListView(
            children: [
              // Секция активных загрузок
              if (activeTasks.isNotEmpty || failedTasks.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.pinkAccent.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.downloading, size: 16, color: Colors.pinkAccent),
                      const SizedBox(width: 8),
                      Text(
                        'В процессе загрузки (${activeTasks.length + failedTasks.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.pinkAccent),
                      ),
                    ],
                  ),
                ),
                ...tasks.where((t) => t.status != DownloadStatus.completed).map((task) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.audio_file, color: Colors.pinkAccent),
                    title: Text(task.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        if (task.status == DownloadStatus.downloading) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: task.totalBytes > 0 ? task.progress : null,
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(task.progress * 100).toInt()}% • ${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}',
                            style: const TextStyle(fontSize: 10, color: Colors.white60),
                          ),
                        ] else ...[
                          Text(
                            task.error ?? 'Ошибка загрузки',
                            style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                          ),
                        ],
                      ],
                    ),
                    trailing: task.status == DownloadStatus.failed
                        ? IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: () => downloadManager.downloadTrack(task.track),
                          )
                        : null,
                  );
                }),
                const Divider(height: 1),
              ],

              // Секция постоянных скачанных треков
              if (downloadedTracks.isNotEmpty)
                ...downloadedTracks.map((track) {
                  final isCurrent = audioController.currentTrack?.id == track.id;
                  int? fileSize;
                  if (track.sourceUrl.isNotEmpty) {
                    try {
                      final f = File(track.sourceUrl);
                      if (f.existsSync()) fileSize = f.lengthSync();
                    } catch (_) {}
                  }

                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: Colors.white.withValues(alpha: 0.06),
                    leading: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
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
                                    child: const Icon(Icons.music_note),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.white12,
                                  child: const Icon(Icons.music_note),
                                ),
                        ),
                        if (isCurrent && audioController.isPlaying)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.graphic_eq, color: Colors.pinkAccent, size: 26),
                          ),
                      ],
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                        color: isCurrent ? Colors.pinkAccent : null,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'СКАЧАНО',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                        if (fileSize != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatBytes(fileSize),
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (track.duration > Duration.zero)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              _formatDuration(track.duration),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            ),
                          ),
                        IconButton(
                          icon: Icon(
                            isCurrent && audioController.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: isCurrent ? Colors.pinkAccent : Colors.greenAccent,
                            size: 28,
                          ),
                          tooltip: 'Слушать оффлайн',
                          onPressed: () {
                            audioController.playTrack(track, playlist: downloadedTracks);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white60),
                          tooltip: 'Удалить с диска',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Удалить трек?'),
                                content: Text('Файл "${track.artist} - ${track.title}" будет удален с диска.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await libraryService.removeTrack(track.id);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      audioController.playTrack(track, playlist: downloadedTracks);
                    },
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
