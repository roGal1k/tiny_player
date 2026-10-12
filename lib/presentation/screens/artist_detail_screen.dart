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
  String _selectedProvider = 'all';

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

  String _getProviderName(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'hitmo':
        return 'Hitmo';
      case 'youtube':
        return 'YouTube';
      case 'audius':
        return 'Audius';
      case 'deezer':
        return 'Deezer';
      case 'soundcloud':
        return 'SoundCloud';
      case 'jamendo':
        return 'Jamendo';
      case 'internet_archive':
        return 'Archive';
      case 'vk':
        return 'VK';
      case 'freesound':
        return 'Freesound';
      case 'local':
        return 'Локальные';
      default:
        return providerId.toUpperCase();
    }
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
      case 'jamendo':
        return Colors.redAccent;
      case 'internet_archive':
        return Colors.blueAccent;
      case 'vk':
        return Colors.lightBlueAccent;
      case 'freesound':
        return Colors.tealAccent;
      case 'local':
        return Colors.tealAccent;
      default:
        return Colors.deepPurpleAccent;
    }
  }

  Widget _buildProviderFilterChips(List<Track> allTracks) {
    final counts = <String, int>{'all': allTracks.length};
    for (final track in allTracks) {
      final pid = track.providerId.toLowerCase();
      counts[pid] = (counts[pid] ?? 0) + 1;
    }

    if (counts.length <= 1) {
      return const SizedBox.shrink();
    }

    final providers = counts.keys.toList();

    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: providers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pid = providers[index];
          final count = counts[pid] ?? 0;
          final isSelected = _selectedProvider == pid;
          final color = pid == 'all' ? Colors.white70 : _getProviderColor(pid);
          final label = pid == 'all' ? 'Все ($count)' : '${_getProviderName(pid)} ($count)';

          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                _selectedProvider = selected ? pid : 'all';
              });
            },
            selectedColor: color.withValues(alpha: 0.25),
            checkmarkColor: color,
            labelStyle: TextStyle(
              color: isSelected ? color : Colors.white70,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? color : Colors.white12,
              ),
            ),
          );
        },
      ),
    );
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
                              errorBuilder: (_, _, _) => Container(
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

                  final allTracks = snapshot.data ?? [];

                  if (allTracks.isEmpty) {
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

                  final filteredTracks = _selectedProvider == 'all'
                      ? allTracks
                      : allTracks
                          .where((t) => t.providerId.toLowerCase() == _selectedProvider.toLowerCase())
                          .toList();

                  final downloadableTracks = filteredTracks.where((t) => t.isDownloadable).toList();

                  return CustomScrollView(
                    slivers: [
                      // Выбор источника треков (как в поиске)
                      SliverToBoxAdapter(
                        child: _buildProviderFilterChips(allTracks),
                      ),

                      // Информационная панель и кнопки управления
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedProvider == 'all'
                                          ? 'Все треки (${allTracks.length})'
                                          : '${_getProviderName(_selectedProvider)}: ${filteredTracks.length} из ${allTracks.length} треков',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                  if (downloadableTracks.isNotEmpty && downloadManager != null)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      icon: const Icon(Icons.download, size: 16),
                                      label: Text('Скачать все (${downloadableTracks.length})'),
                                      onPressed: () async {
                                        final count = await downloadManager.downloadAll(downloadableTracks);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Добавлено в загрузки: $count треков'),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
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
                                        filteredTracks.isEmpty
                                            ? 'Слушать'
                                            : 'Слушать всё (${filteredTracks.length})',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: filteredTracks.isEmpty
                                          ? null
                                          : () {
                                              audioController.playTrack(
                                                filteredTracks.first,
                                                playlist: filteredTracks,
                                              );
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
                                    onPressed: filteredTracks.isEmpty
                                        ? null
                                        : () {
                                            final shuffled = List<Track>.from(filteredTracks)..shuffle();
                                            audioController.playTrack(
                                              shuffled.first,
                                              playlist: shuffled,
                                            );
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Пустое состояние для выбранного источника
                      if (filteredTracks.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.music_off, size: 44, color: Colors.white38),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Нет треков от ${_getProviderName(_selectedProvider)}',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed: () => setState(() => _selectedProvider = 'all'),
                                    child: const Text('Показать все источники'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        // Tracks List
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final track = filteredTracks[index];
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
                                          errorBuilder: (_, _, _) => Container(
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
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withValues(alpha: 0.8),
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
                                      audioController.playTrack(track, playlist: filteredTracks);
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                audioController.playTrack(track, playlist: filteredTracks);
                              },
                            );
                          },
                          childCount: filteredTracks.length,
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
