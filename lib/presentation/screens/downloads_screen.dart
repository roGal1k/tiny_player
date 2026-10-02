import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/download_manager.dart';
import '../controllers/audio_player_controller.dart';
import '../../domain/models/track.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final downloadManager = context.watch<DownloadManager>();
    final audioController = context.read<AudioPlayerController>();
    final tasks = downloadManager.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text(
                    'No downloads yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for tracks with download availability to save them locally.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final track = task.track;

                return ListTile(
                  leading: ClipRRect(
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
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                      ] else if (task.status == DownloadStatus.completed) ...[
                        const Row(
                          children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
                            SizedBox(width: 4),
                            Text('Downloaded to library', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.error, size: 14, color: Colors.redAccent),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.error ?? 'Download failed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: task.status == DownloadStatus.completed && task.savedFilePath != null
                      ? IconButton(
                          icon: const Icon(Icons.play_circle_filled, size: 30, color: Colors.greenAccent),
                          tooltip: 'Play downloaded file',
                          onPressed: () {
                            final completedTracks = tasks
                                .where((t) =>
                                    t.status == DownloadStatus.completed &&
                                    t.savedFilePath != null)
                                .map((t) => Track(
                                      id: 'local_${t.savedFilePath.hashCode}',
                                      providerId: 'local',
                                      title: t.track.title,
                                      artist: t.track.artist,
                                      album: t.track.album,
                                      artworkUrl: t.track.artworkUrl,
                                      duration: t.track.duration,
                                      isStreamable: true,
                                      isDownloadable: false,
                                      sourceUrl: t.savedFilePath!,
                                    ))
                                .toList();

                            final localTrack = Track(
                              id: 'local_${task.savedFilePath.hashCode}',
                              providerId: 'local',
                              title: track.title,
                              artist: track.artist,
                              album: track.album,
                              artworkUrl: track.artworkUrl,
                              duration: track.duration,
                              isStreamable: true,
                              isDownloadable: false,
                              sourceUrl: task.savedFilePath!,
                            );
                            audioController.playTrack(localTrack, playlist: completedTracks);
                          },
                        )
                      : task.status == DownloadStatus.failed
                          ? IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Retry download',
                              onPressed: () => downloadManager.downloadTrack(track),
                            )
                          : null,
                );
              },
            ),
    );
  }
}
