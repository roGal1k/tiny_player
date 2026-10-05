import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/providers/provider_registry.dart';
import '../../domain/models/track.dart';
import '../controllers/audio_player_controller.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/video_launcher_service.dart';
import '../../data/services/audio_cache_service.dart';
import '../../data/local/database_helper.dart';

enum SearchSortMode {
  defaultMix,
  byPlatform,
  byArtist,
  byTitle,
  byDuration,
}

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
  bool _isOfflineMode = false;
  String? _error;
  String _activeCategory = '';
  String _selectedProvider = 'all';
  SearchSortMode _sortMode = SearchSortMode.defaultMix;

  List<Track> get _filteredResults {
    if (_selectedProvider == 'all') return _results;
    return _results
        .where((t) => t.providerId.toLowerCase() == _selectedProvider.toLowerCase())
        .toList();
  }

  List<Track> get _sortedAndFilteredResults {
    final list = _filteredResults;
    if (_sortMode == SearchSortMode.defaultMix) return list;

    final copy = List<Track>.from(list);
    switch (_sortMode) {
      case SearchSortMode.byPlatform:
        copy.sort((a, b) {
          final cmp = a.providerId.compareTo(b.providerId);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case SearchSortMode.byArtist:
        copy.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case SearchSortMode.byTitle:
        copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SearchSortMode.byDuration:
        copy.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case SearchSortMode.defaultMix:
        break;
    }
    return copy;
  }

  String _getSortModeName(SearchSortMode mode) {
    switch (mode) {
      case SearchSortMode.defaultMix:
        return 'Микс (по умолчанию)';
      case SearchSortMode.byPlatform:
        return 'По платформам';
      case SearchSortMode.byArtist:
        return 'По исполнителю (А-Я)';
      case SearchSortMode.byTitle:
        return 'По названию (А-Я)';
      case SearchSortMode.byDuration:
        return 'По длительности';
    }
  }

  final List<(String, IconData)> _categories = const [
    ('Топ Сегодня', Icons.local_fire_department),
    ('Новинки', Icons.new_releases),
    ('Hitmo Чарты', Icons.music_video),
    ('YouTube Music', Icons.smart_display),
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
      _isOfflineMode = false;
    });

    try {
      final registry = context.read<ProviderRegistry>();
      List<Track> tracks = [];
      if (category == 'Топ Сегодня' || category == 'Hitmo Чарты') {
        tracks = await registry.getPopularTracks();
      } else if (category == 'Новинки') {
        tracks = await registry.getNewReleases();
      } else if (category == 'YouTube Music') {
        final yt = registry.allProviders.where((p) => p.providerId == 'youtube').firstOrNull;
        if (yt != null && registry.isProviderEnabled('youtube')) {
          tracks = await yt.search('Popular Music Hits');
        } else {
          tracks = await registry.searchAcrossProviders('Popular Music Hits');
        }
      } else if (category == 'SoundCloud') {
        tracks = await registry.searchAcrossProviders('SoundCloud Hits');
      } else {
        tracks = await registry.getTracksByGenre(category);
      }

      if (tracks.isEmpty) {
        // Если сеть не вернула треки (например, нет интернета), проверяем локальные треки
        final localTracks = await DatabaseHelper.instance.searchLocalTracks('');
        if (localTracks.isNotEmpty && mounted) {
          setState(() {
            _selectedProvider = 'all';
            _results = localTracks;
            _isOfflineMode = true;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _selectedProvider = 'all';
          _results = tracks;
        });
      }
    } catch (e) {
      // Офлайн фоллбэк при сетевых ошибках
      try {
        final localTracks = await DatabaseHelper.instance.searchLocalTracks('');
        if (localTracks.isNotEmpty && mounted) {
          setState(() {
            _selectedProvider = 'all';
            _results = localTracks;
            _isOfflineMode = true;
            _error = null;
          });
          return;
        }
      } catch (_) {}

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
      _isOfflineMode = false;
    });

    try {
      final registry = context.read<ProviderRegistry>();
      final results = await registry.searchAcrossProviders(query);

      if (results.isEmpty) {
        // Если поиск по сети пуст (например, нет интернета), ищем по локальной базе и кэшу
        final localResults = await DatabaseHelper.instance.searchLocalTracks(query);
        if (localResults.isNotEmpty && mounted) {
          setState(() {
            _selectedProvider = 'all';
            _results = localResults;
            _isOfflineMode = true;
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _selectedProvider = 'all';
          _results = results;
        });
      }
    } catch (e) {
      // Офлайн поиск при сетевых ошибках
      try {
        final localResults = await DatabaseHelper.instance.searchLocalTracks(query);
        if (localResults.isNotEmpty && mounted) {
          setState(() {
            _selectedProvider = 'all';
            _results = localResults;
            _isOfflineMode = true;
            _error = null;
          });
          return;
        }
      } catch (_) {}

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

  IconData _getProviderIcon(String id) {
    switch (id.toLowerCase()) {
      case 'hitmo':
        return Icons.music_video;
      case 'youtube':
        return Icons.smart_display;
      case 'vk':
        return Icons.record_voice_over;
      case 'soundcloud':
        return Icons.cloud_queue;
      case 'jamendo':
        return Icons.album;
      case 'internet_archive':
        return Icons.archive;
      case 'freesound':
        return Icons.graphic_eq;
      case 'local':
        return Icons.folder;
      default:
        return Icons.library_music;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final audioController = context.watch<AudioPlayerController>();
    final downloadManager = context.watch<DownloadManager>();
    final cacheService = context.watch<AudioCacheService?>();

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
      body: _buildBody(audioController, downloadManager, cacheService),
    );
  }

  Widget _buildBody(AudioPlayerController audioController, DownloadManager downloadManager, AudioCacheService? cacheService) {
    return Column(
      children: [
        if (_isOfflineMode) _buildOfflineBanner(),
        _buildCategoryChips(),
        _buildActiveDownloadsBanner(downloadManager),
        if (_results.isNotEmpty) ...[
          _buildProviderFilterChips(),
          _buildBatchActionBar(downloadManager),
        ],
        Expanded(
          child: _buildResultsList(audioController, downloadManager, cacheService),
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.amber.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⚡ Офлайн-режим • Доступно ${_results.length} сохраненных треков',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Colors.amber,
            ),
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _performSearch();
              } else {
                _loadCategory(_activeCategory.isNotEmpty ? _activeCategory : 'Топ Сегодня');
              }
            },
            child: const Text('Повторить сеть'),
          ),
        ],
      ),
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

    if (counts.length <= 1) {
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
    final tracksToProcess = _sortedAndFilteredResults;
    final downloadableTracks = tracksToProcess.where((t) => t.isDownloadable).toList();
    final downloadableCount = downloadableTracks.length;

    // Per-provider counts summary
    final Map<String, int> providerCounts = {};
    for (final track in _results) {
      final name = _getProviderName(track.providerId);
      providerCounts[name] = (providerCounts[name] ?? 0) + 1;
    }
    final breakdown = providerCounts.entries.map((e) => '${e.key}: ${e.value}').join(' • ');

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
                      (breakdown.isNotEmpty ? ' ($breakdown)' : '') +
                      (_sortMode != SearchSortMode.defaultMix ? ' • ${_getSortModeName(_sortMode)}' : '') +
                      (downloadableCount > 0 ? ' • $downloadableCount доступны' : ''),
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                ),
              ],
            ),
          ),
          PopupMenuButton<SearchSortMode>(
            tooltip: 'Сортировка (${_getSortModeName(_sortMode)})',
            icon: Icon(
              _sortMode == SearchSortMode.defaultMix ? Icons.swap_vert : Icons.sort,
              size: 20,
              color: _sortMode == SearchSortMode.defaultMix ? Colors.white70 : Colors.pinkAccent,
            ),
            onSelected: (mode) {
              setState(() {
                _sortMode = mode;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: SearchSortMode.defaultMix,
                child: Row(
                  children: [
                    Icon(Icons.shuffle, size: 18),
                    SizedBox(width: 8),
                    Text('По умолчанию (микс)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SearchSortMode.byPlatform,
                child: Row(
                  children: [
                    Icon(Icons.apps, size: 18, color: Colors.pinkAccent),
                    SizedBox(width: 8),
                    Text('По платформам (источникам)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SearchSortMode.byArtist,
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 18),
                    SizedBox(width: 8),
                    Text('По исполнителю (А-Я)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SearchSortMode.byTitle,
                child: Row(
                  children: [
                    Icon(Icons.title, size: 18),
                    SizedBox(width: 8),
                    Text('По названию (А-Я)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SearchSortMode.byDuration,
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('По длительности'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
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

  Widget _buildResultsList(AudioPlayerController audioController, DownloadManager downloadManager, AudioCacheService? cacheService) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _activeCategory.isNotEmpty
                      ? _loadCategory(_activeCategory)
                      : _performSearch(),
                  child: const Text('Повторить'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.offline_pin, size: 18),
                  label: const Text('Офлайн-треки'),
                  onPressed: () async {
                    final localTracks = await DatabaseHelper.instance.searchLocalTracks('');
                    if (mounted) {
                      setState(() {
                        _selectedProvider = 'all';
                        _results = localTracks;
                        _isOfflineMode = true;
                        _error = null;
                      });
                    }
                  },
                ),
              ],
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
                    avatar: const Icon(Icons.music_video, size: 18, color: Colors.pinkAccent),
                    label: const Text('Hitmo Чарты'),
                    onPressed: () => _loadCategory('Hitmo Чарты'),
                  ),
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
                    avatar: const Icon(Icons.smart_display, size: 18, color: Colors.redAccent),
                    label: const Text('YouTube Music'),
                    onPressed: () => _loadCategory('YouTube Music'),
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

    final tracksToDisplay = _sortedAndFilteredResults;

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

    final isPlatformGroup = _sortMode == SearchSortMode.byPlatform && _selectedProvider == 'all';

    return ListView.builder(
      key: const PageStorageKey<String>('search_screen_results_list'),
      itemCount: tracksToDisplay.length,
      itemBuilder: (context, index) {
        final track = tracksToDisplay[index];
        final isCurrent = audioController.currentTrack?.id == track.id &&
            audioController.currentTrack?.providerId == track.providerId;
        final providerColor = _getProviderColor(track.providerId);
        final isTrackCached = cacheService?.isCached(track) ?? false;

        final showHeader = isPlatformGroup &&
            (index == 0 || tracksToDisplay[index].providerId != tracksToDisplay[index - 1].providerId);

        final tile = ListTile(
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
              if (isTrackCached) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.offline_pin, size: 10, color: Colors.greenAccent),
                      SizedBox(width: 2),
                      Text(
                        'ОФЛАЙН',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
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

        if (showHeader) {
          final pid = track.providerId;
          final providerName = _getProviderName(pid);
          final providerColor = _getProviderColor(pid);
          final icon = _getProviderIcon(pid);
          final count = tracksToDisplay.where((t) => t.providerId == pid).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: index == 0 ? 8 : 16,
                  bottom: 4,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: providerColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: providerColor.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: providerColor),
                    const SizedBox(width: 8),
                    Text(
                      providerName.toUpperCase(),
                      style: TextStyle(
                        color: providerColor,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$count треков',
                      style: TextStyle(
                        color: providerColor.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              tile,
            ],
          );
        }

        return tile;
      },
    );
  }
}

