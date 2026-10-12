import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/track.dart';
import '../../data/services/artist_service.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/local_library_service.dart';
import '../../data/services/video_launcher_service.dart';
import '../controllers/audio_player_controller.dart';
import '../widgets/mini_player_widget.dart';

class ArtistDetailScreen extends StatefulWidget {
  final Artist artist;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  late Future<List<Track>> _tracksFuture;
  late Artist _currentArtist;

  @override
  void initState() {
    super.initState();
    _currentArtist = widget.artist;
    _loadTracks();
  }

  void _loadTracks() {
    final artistService = Provider.of<ArtistService?>(context, listen: false);
    if (artistService != null) {
      _tracksFuture = artistService.getArtistTracks(_currentArtist.name);
    } else {
      _tracksFuture = Future.value([]);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Color _getProviderColor(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'deezer':
        return const Color(0xFFFEAA2D);
      case 'hitmo':
        return Colors.pinkAccent;
      case 'soundcloud':
        return Colors.orangeAccent;
      case 'audius':
        return const Color(0xFFCC0FE0);
      case 'local':
        return Colors.tealAccent;
      default:
        return Colors.deepPurpleAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artistService = Provider.of<ArtistService?>(context);
    final isFav = artistService?.isFavorite(_currentArtist.name) ?? false;
    final audioController = Provider.of<AudioPlayerController>(context);
    final downloadManager = Provider.of<DownloadManager?>(context);
    final libraryService = Provider.of<LocalLibraryService?>(context);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    expandedHeight: 260.0,
                    pinned: true,
                    title: innerBoxIsScrolled ? Text(_currentArtist.name) : null,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_currentArtist.artworkUrl != null &&
                              _currentArtist.artworkUrl!.isNotEmpty)
                            Image.network(
                              _currentArtist.artworkUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary.withValues(alpha: 0.6),
                                    theme.colorScheme.surface,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          // Dark gradient overlay for readability
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.black.withValues(alpha: 0.85),
                                ],
                              ),
                            ),
                          ),
                          // Center content
                          Positioned(
                            bottom: 20,
                            left: 16,
                            right: 16,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 46,
                                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  backgroundImage: (_currentArtist.artworkUrl != null &&
                                          _currentArtist.artworkUrl!.isNotEmpty)
                                      ? NetworkImage(_currentArtist.artworkUrl!)
                                      : null,
                                  child: (_currentArtist.artworkUrl == null ||
                                          _currentArtist.artworkUrl!.isEmpty)
                                      ? const Icon(Icons.person, size: 48, color: Colors.white70)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _currentArtist.name,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      if (_currentArtist.trackCount != null &&
                                          _currentArtist.trackCount! > 0)
                                        Text(
                                          _currentArtist.providerId == 'deezer'
                                              ? '${_currentArtist.trackCount} слушателей'
                                              : '${_currentArtist.trackCount} треков в медиатеке',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white70,
                                          ),
                                        )
                                      else
                                        const Text(
                                          'Исполнитель',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.white70,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton.filledTonal(
                                  icon: Icon(
                                    isFav ? Icons.favorite : Icons.favorite_border,
                                    color: isFav ? Colors.redAccent : Colors.white70,
                                    size: 26,
                                  ),
                                  tooltip: isFav
                                      ? 'Удалить из избранных'
                                      : 'Добавить в избранные исполнители',
                                  onPressed: () async {
                                    if (artistService != null) {
                                      final added =
                                          await artistService.toggleFavorite(_currentArtist);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              added
                                                  ? 'Исполнитель ${_currentArtist.name} добавлен в избранное ❤️'
                                                  : 'Исполнитель удалён из избранного',
                                            ),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: FutureBuilder<List<Track>>(
                future: _tracksFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Поиск треков исполнителя...'),
                        ],
                      ),
                    );
                  }

                  final tracks = snapshot.data ?? [];

                  if (tracks.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.music_off, size: 48, color: Colors.white38),
                            const SizedBox(height: 12),
                            Text(
                              'Треки не найдены',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Попробуйте обновить или выполнить поиск в разделе «Поиск».',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _loadTracks();
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Повторить попытку'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return CustomScrollView(
                    slivers: [
                      // Action buttons: "Play All" and "Shuffle"
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: theme.colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(
                                    'Слушать всё (${tracks.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    audioController.playTrack(tracks.first, playlist: tracks);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Перемешать'),
                                onPressed: () {
                                  final shuffled = List<Track>.from(tracks)..shuffle();
                                  audioController.playTrack(shuffled.first, playlist: shuffled);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Tracks List
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final track = tracks[index];
                            final isCurrent = audioController.currentTrack?.id == track.id;
                            final isPlaying = isCurrent && audioController.isPlaying;
                            final isBuffering = isCurrent && audioController.isBuffering;
                            final providerColor = _getProviderColor(track.providerId);
                            final isTrackFav = libraryService?.isFavorite(track.id) ?? false;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              leading: SizedBox(
                                width: 44,
                                height: 44,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (track.artworkUrl != null &&
                                          track.artworkUrl!.isNotEmpty)
                                        Image.network(
                                          track.artworkUrl!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: theme.colorScheme.surfaceContainerHighest,
                                            child: const Icon(Icons.music_note, size: 20),
                                          ),
                                        )
                                      else
                                        Container(
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: const Icon(Icons.music_note, size: 20),
                                        ),
                                      if (isCurrent)
                                        Container(
                                          color: Colors.black45,
                                          child: Icon(
                                            isPlaying ? Icons.equalizer : Icons.pause,
                                            color: providerColor,
                                            size: 24,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  color: isCurrent ? providerColor : null,
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
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: providerColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      track.album ?? track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  if (track.duration > Duration.zero)
                                    Text(
                                      _formatDuration(track.duration),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.5),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (libraryService != null)
                                    IconButton(
                                      icon: Icon(
                                        isTrackFav ? Icons.favorite : Icons.favorite_border,
                                        size: 20,
                                        color: isTrackFav ? Colors.redAccent : Colors.white60,
                                      ),
                                      tooltip: isTrackFav
                                          ? 'В избранном'
                                          : 'Добавить трек в избранное',
                                      onPressed: () => libraryService.toggleFavorite(track),
                                    ),
                                  if (track.providerId == 'youtube')
                                    IconButton(
                                      icon: const Icon(
                                        Icons.smart_display_outlined,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      tooltip: 'Клип',
                                      onPressed: () {
                                        final launcher =
                                            VideoLauncherService(audioController.registry);
                                        launcher.openVideo(
                                          track,
                                          audioController: audioController,
                                          context: context,
                                        );
                                      },
                                    ),
                                  if (track.isDownloadable && downloadManager != null)
                                    Builder(
                                      builder: (ctx) {
                                        final taskKey = '${track.providerId}_${track.id}';
                                        final task = downloadManager.getTask(taskKey);
                                        if (task?.status == DownloadStatus.completed) {
                                          return const Icon(
                                            Icons.check_circle,
                                            size: 20,
                                            color: Colors.greenAccent,
                                          );
                                        }
                                        return IconButton(
                                          icon: const Icon(Icons.download, size: 20),
                                          tooltip: 'Скачать',
                                          onPressed: () {
                                            downloadManager.downloadTrack(track);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Скачивание: ${track.title}'),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  IconButton(
                                    icon: isBuffering
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Icon(
                                            isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: isCurrent ? providerColor : null,
                                            size: 24,
                                          ),
                                    onPressed: () {
                                      audioController.playTrack(track, playlist: tracks);
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                audioController.playTrack(track, playlist: tracks);
                              },
                            );
                          },
                          childCount: tracks.length,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const MiniPlayerWidget(),
        ],
      ),
    );
  }
}
