import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/providers/provider_registry.dart';
import '../../domain/models/track.dart';
import '../controllers/audio_player_controller.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/video_launcher_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  bool get wantKeepAlive => true;
  List<Track> _results = [];
  bool _isLoading = false;
  String? _error;
  String _activeCategory = '';
  String _selectedProvider = 'all';

  List<Track> get _filteredResults {
    if (_selectedProvider == 'all') return _results;
    return _results
        .where((t) => t.providerId.toLowerCase() == _selectedProvider.toLowerCase())
        .toList();
  }

  final List<(String, IconData)> _categories = const [
    ('Топ Сегодня', Icons.local_fire_department),
    ('Новинки', Icons.new_releases),
    ('SoundCloud', Icons.graphic_eq),
    ('Рок', Icons.music_note),
    ('Electronic', Icons.headphones),
    ('Lo-Fi', Icons.waves),
    ('Поп-хиты', Icons.mic),
    ('Джаз', Icons.album),
  ];

  Future<void> _loadCategory(String category) async {
    setState(() {
      _activeCategory = category;
      _isLoading = true;
      _error = null;
    });

    try {
      final registry = context.read<ProviderRegistry>();
      List<Track> tracks = [];
      if (category == 'Топ Сегодня') {
        tracks = await registry.getPopularTracks();
      } else if (category == 'Новинки') {
        tracks = await registry.getNewReleases();
      } else if (category == 'SoundCloud') {
        tracks = await registry.searchAcrossProviders('SoundCloud Hits');
      } else {
        tracks = await registry.getTracksByGenre(category);
      }

      if (mounted) {
        setState(() {
          _selectedProvider = 'all';
          _results = tracks;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _loadCategory(_activeCategory);
      return;
    }

    setState(() {
      _activeCategory = '';
      _isLoading = true;
      _error = null;
    });

    try {
      final registry = context.read<ProviderRegistry>();
      final results = await registry.searchAcrossProviders(query);
      if (mounted) {
        setState(() {
          _selectedProvider = 'all';
          _results = results;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      default:
        return Colors.deepPurpleAccent;
    }
  }

  String _getProviderName(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'hitmo':
        return 'Hitmo';
      case 'youtube':
        return 'YouTube';
      case 'soundcloud':
        return 'SoundCloud';
      case 'jamendo':
        return 'Jamendo';
      case 'internet_archive':
        return 'Archive';
      case 'freesound':
        return 'Freesound';
      case 'vk':
        return 'VK';
      case 'local':
        return 'Local';
      default:
        return providerId.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final audioController = context.watch<AudioPlayerController>();
    final downloadManager = context.watch<DownloadManager>();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search across providers (Hitmo, SoundCloud, Jamendo)...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                      _loadCategory('Топ Сегодня');
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _performSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _performSearch,
          ),
        ],
      ),
      body: _buildBody(audioController, downloadManager),
    );
  }

  Widget _buildBody(AudioPlayerController audioController, DownloadManager downloadManager) {
    return Column(
      children: [
        _buildCategoryChips(),
        _buildActiveDownloadsBanner(downloadManager),
        if (_results.isNotEmpty) ...[
          _buildProviderFilterChips(),
          _buildBatchActionBar(downloadManager),
        ],
        Expanded(
          child: _buildResultsList(audioController, downloadManager),
        ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _categories[index];
          final categoryName = item.$1;
          final categoryIcon = item.$2;
          final isSelected = _activeCategory == categoryName && _searchController.text.trim().isEmpty;
          return FilterChip(
            avatar: Icon(categoryIcon, size: 16, color: isSelected ? Colors.pinkAccent : Colors.white70),
            label: Text(categoryName),
            selected: isSelected,
            onSelected: (selected) {
              _searchController.clear();
              _loadCategory(categoryName);
            },
            selectedColor: Colors.pinkAccent.withOpacity(0.25),
            checkmarkColor: Colors.pinkAccent,
            labelStyle: TextStyle(
              color: isSelected ? Colors.pinkAccent : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12.5,
            ),
            backgroundColor: Colors.white.withOpacity(0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? Colors.pinkAccent : Colors.white12,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveDownloadsBanner(DownloadManager downloadManager) {
    if (downloadManager.activeDownloadsCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.pinkAccent.withOpacity(0.12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Скачивание очереди: ${downloadManager.activeDownloadsCount} активных загрузок',
              style: const TextStyle(fontSize: 12, color: Colors.pinkAccent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderFilterChips() {
    if (_results.isEmpty) return const SizedBox.shrink();

    final Map<String, int> counts = {'all': _results.length};
    for (final track in _results) {
      final pid = track.providerId.toLowerCase();
      counts[pid] = (counts[pid] ?? 0) + 1;
    }

    if (counts.length <= 2) {
      return const SizedBox.shrink();
    }

    final providers = counts.keys.toList();

    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: providers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
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
            selectedColor: color.withOpacity(0.25),
            checkmarkColor: color,
            labelStyle: TextStyle(
              color: isSelected ? color : Colors.white70,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.white.withOpacity(0.04),
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

  Widget _buildBatchActionBar(DownloadManager downloadManager) {
    final tracksToProcess = _filteredResults;
    final downloadableTracks = tracksToProcess.where((t) => t.isDownloadable).toList();
    final downloadableCount = downloadableTracks.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _searchController.text.isNotEmpty
                      ? 'Результаты: "${_searchController.text.trim()}"'
                      : _activeCategory,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Показано ${tracksToProcess.length} из ${_results.length} треков' +
                      (downloadableCount > 0 ? ' • $downloadableCount доступны' : ''),
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                ),
              ],
            ),
          ),
          if (downloadableCount > 0) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.download, size: 16),
              label: Text('Все ($downloadableCount)'),
              onPressed: () async {
                final count = await downloadManager.downloadAll(tracksToProcess);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Начата загрузка $count треков в библиотеку'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.filter_5, size: 16),
              label: const Text('Топ 5'),
              onPressed: () async {
                final count = await downloadManager.downloadTopN(tracksToProcess, 5);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Начата загрузка топ-$count треков'),
                    ),
                  );
                }
              },
            ),
            if (downloadableCount >= 10) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.filter_9_plus, size: 16),
                label: const Text('Топ 10'),
                onPressed: () async {
                  final count = await downloadManager.downloadTopN(tracksToProcess, 10);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Начата загрузка топ-$count треков'),
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildResultsList(AudioPlayerController audioController, DownloadManager downloadManager) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка загрузки: $_error', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _activeCategory.isNotEmpty
                  ? _loadCategory(_activeCategory)
                  : _performSearch(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      if (_searchController.text.isNotEmpty || _activeCategory.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_off_outlined, size: 48, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text('Треки не найдены. Попробуйте другую категорию или поиск.'),
            ],
          ),
        );
      }

      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_outlined, size: 64, color: Colors.pinkAccent.withOpacity(0.8)),
              const SizedBox(height: 16),
              const Text(
                'Чарты и Рекомендации',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите подборку выше или начните поиск музыки для стриминга и скачивания',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.whatshot, size: 18, color: Colors.pinkAccent),
                    label: const Text('Топ Сегодня'),
                    onPressed: () => _loadCategory('Топ Сегодня'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.new_releases, size: 18, color: Colors.amberAccent),
                    label: const Text('Новинки'),
                    onPressed: () => _loadCategory('Новинки'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.graphic_eq, size: 18, color: Colors.orangeAccent),
                    label: const Text('SoundCloud'),
                    onPressed: () => _loadCategory('SoundCloud'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final tracksToDisplay = _filteredResults;

    if (tracksToDisplay.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_alt_off, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('Нет треков от ${_getProviderName(_selectedProvider)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _selectedProvider = 'all'),
              child: const Text('Показать все треки'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('search_screen_results_list'),
      itemCount: tracksToDisplay.length,
      itemBuilder: (context, index) {
        final track = tracksToDisplay[index];
        final isCurrent = audioController.currentTrack?.id == track.id &&
            audioController.currentTrack?.providerId == track.providerId;
        final providerColor = _getProviderColor(track.providerId);

        return ListTile(
          selected: isCurrent,
          selectedTileColor: Colors.white.withOpacity(0.06),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                    ? Image.network(
                        track.artworkUrl!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 50,
                          height: 50,
                          color: Colors.white10,
                          child: const Icon(Icons.music_note),
                        ),
                      )
                    : Container(
                        width: 50,
                        height: 50,
                        color: Colors.white10,
                        child: const Icon(Icons.music_note),
                      ),
              ),
              if (isCurrent && audioController.isPlaying)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.graphic_eq, color: providerColor, size: 28),
                ),
            ],
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: providerColor.withOpacity(0.2),
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
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.isStreamable)
                IconButton(
                  icon: isCurrent && audioController.isBuffering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isCurrent && audioController.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: isCurrent ? providerColor : null,
                        ),
                  onPressed: () => audioController.playTrack(track, playlist: tracksToDisplay),
                ),
              if (track.providerId == 'youtube')
                IconButton(
                  icon: const Icon(Icons.smart_display_outlined, color: Colors.redAccent),
                  tooltip: 'Смотреть видео / клип',
                  onPressed: () {
                    final launcher = VideoLauncherService(audioController.registry);
                    launcher.openVideo(track, audioController: audioController, context: context);
                  },
                ),
              if (track.isDownloadable)
                Builder(
                  builder: (context) {
                    final taskKey = '${track.providerId}_${track.id}';
                    final task = downloadManager.getTask(taskKey);

                    if (task?.status == DownloadStatus.downloading) {
                      return SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: CircularProgressIndicator(
                            value: task!.progress > 0 ? task.progress : null,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    if (task?.status == DownloadStatus.completed) {
                      return const IconButton(
                        icon: Icon(Icons.check_circle, size: 20, color: Colors.greenAccent),
                        tooltip: 'Downloaded to library',
                        onPressed: null,
                      );
                    }

                    return IconButton(
                      icon: const Icon(Icons.download, size: 20),
                      tooltip: 'Download track to local library',
                      onPressed: () {
                        downloadManager.downloadTrack(track);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Started download: ${track.title}')),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
          onTap: () {
            if (track.isStreamable) {
              audioController.playTrack(track, playlist: tracksToDisplay);
            }
          },
        );
      },
    );
  }
}

