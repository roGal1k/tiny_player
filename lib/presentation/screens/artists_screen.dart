import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/artist.dart';
import '../../data/services/artist_service.dart';
import 'artist_detail_screen.dart';

enum ArtistFilterTab {
  favorites,
  library,
  search,
}

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  ArtistFilterTab _currentTab = ArtistFilterTab.favorites;
  List<Artist> _searchResults = [];
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _lastQuery = '';
        _searchResults = [];
        _isSearching = false;
        if (_currentTab == ArtistFilterTab.search) {
          _currentTab = ArtistFilterTab.favorites;
        }
      });
      return;
    }

    setState(() {
      _lastQuery = clean;
      _isSearching = true;
      _currentTab = ArtistFilterTab.search;
    });

    final artistService = Provider.of<ArtistService?>(context, listen: false);
    if (artistService != null) {
      final results = await artistService.searchArtists(clean);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final artistService = Provider.of<ArtistService?>(context);

    final favorites = artistService?.favoriteArtists ?? [];
    final libraryArtists = artistService?.getArtistsFromLibrary() ?? [];

    List<Artist> displayList;
    switch (_currentTab) {
      case ArtistFilterTab.favorites:
        displayList = favorites;
        break;
      case ArtistFilterTab.library:
        displayList = libraryArtists;
        break;
      case ArtistFilterTab.search:
        displayList = _searchResults;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.mic, color: Colors.deepPurpleAccent),
            SizedBox(width: 8),
            Text('Исполнители'),
          ],
        ),
        actions: [
          if (artistService != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
              onPressed: () {
                artistService.loadFavorites();
                if (_lastQuery.isNotEmpty) {
                  _performSearch(_lastQuery);
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search input bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Поиск исполнителя (Queen, Кино, Miyagi...)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Избранные (${favorites.length})'),
                    selected: _currentTab == ArtistFilterTab.favorites,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _currentTab = ArtistFilterTab.favorites);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Из медиатеки (${libraryArtists.length})'),
                    selected: _currentTab == ArtistFilterTab.library,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _currentTab = ArtistFilterTab.library);
                      }
                    },
                  ),
                  if (_lastQuery.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        _isSearching
                            ? 'Поиск...'
                            : 'Результаты: "$_lastQuery" (${_searchResults.length})',
                      ),
                      selected: _currentTab == ArtistFilterTab.search,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _currentTab = ArtistFilterTab.search);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Main Content
          Expanded(
            child: _buildBody(
              theme: theme,
              artistService: artistService,
              displayList: displayList,
              favorites: favorites,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required ThemeData theme,
    required ArtistService? artistService,
    required List<Artist> displayList,
    required List<Artist> favorites,
  }) {
    if (_isSearching && _currentTab == ArtistFilterTab.search) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Поиск исполнителей онлайн...'),
          ],
        ),
      );
    }

    if (displayList.isEmpty) {
      return _buildEmptyState(theme);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        if (isWide) {
          // Grid layout for desktop / tablets
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.85,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final artist = displayList[index];
              return _buildArtistCard(
                theme: theme,
                artist: artist,
                artistService: artistService,
              );
            },
          );
        }

        // List layout for mobile
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: displayList.length,
          itemBuilder: (context, index) {
            final artist = displayList[index];
            return _buildArtistListTile(
              theme: theme,
              artist: artist,
              artistService: artistService,
            );
          },
        );
      },
    );
  }

  Widget _buildArtistCard({
    required ThemeData theme,
    required Artist artist,
    required ArtistService? artistService,
  }) {
    final isFav = artistService?.isFavorite(artist.name) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(artist: artist),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFav
                ? Colors.redAccent.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              backgroundImage: (artist.artworkUrl != null && artist.artworkUrl!.isNotEmpty)
                  ? NetworkImage(artist.artworkUrl!)
                  : null,
              child: (artist.artworkUrl == null || artist.artworkUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 40, color: Colors.white60)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: (artist.trackCount != null && artist.trackCount! > 0)
                      ? Text(
                          artist.providerId == 'deezer'
                              ? '${artist.trackCount} фанатов'
                              : '${artist.trackCount} треков',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        )
                      : Text(
                          isFav ? 'В избранном ❤️' : 'Исполнитель',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isFav ? Colors.redAccent : Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                ),
                IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.redAccent : Colors.white60,
                    size: 20,
                  ),
                  onPressed: () {
                    artistService?.toggleFavorite(artist);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistListTile({
    required ThemeData theme,
    required Artist artist,
    required ArtistService? artistService,
  }) {
    final isFav = artistService?.isFavorite(artist.name) ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFav
              ? Colors.redAccent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
          backgroundImage: (artist.artworkUrl != null && artist.artworkUrl!.isNotEmpty)
              ? NetworkImage(artist.artworkUrl!)
              : null,
          child: (artist.artworkUrl == null || artist.artworkUrl!.isEmpty)
              ? const Icon(Icons.person, size: 26, color: Colors.white60)
              : null,
        ),
        title: Text(
          artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Row(
          children: [
            if (isFav)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('❤️ В избранном', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
            if (artist.trackCount != null && artist.trackCount! > 0)
              Text(
                artist.providerId == 'deezer'
                    ? '${artist.trackCount} слушателей'
                    : '${artist.trackCount} треков в медиатеке',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.redAccent : Colors.white60,
                size: 24,
              ),
              tooltip: isFav ? 'Удалить из избранных' : 'В избранное',
              onPressed: () {
                artistService?.toggleFavorite(artist);
              },
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    String title;
    String subtitle;
    IconData icon;

    switch (_currentTab) {
      case ArtistFilterTab.favorites:
        title = 'Нет избранных исполнителей';
        subtitle =
            'Ищите любимых музыкантов через строку поиска выше или сохраняйте их прямо с экрана плеера ❤️';
        icon = Icons.favorite_border;
        break;
      case ArtistFilterTab.library:
        title = 'В медиатеке нет исполнителей';
        subtitle = 'Сканируйте папку с музыкой на главном экране или скачивайте треки в приложении.';
        icon = Icons.library_music_outlined;
        break;
      case ArtistFilterTab.search:
        title = 'Ничего не найдено';
        subtitle = 'Попробуйте изменить поисковый запрос или проверить название исполнителя.';
        icon = Icons.search_off;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            if (_currentTab == ArtistFilterTab.favorites) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Найти исполнителей'),
                onPressed: () {
                  _searchController.text = 'Queen';
                  _onSearchChanged('Queen');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
