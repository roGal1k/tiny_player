import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../domain/models/artist.dart';
import '../../domain/models/track.dart';
import '../local/database_helper.dart';
import '../providers/provider_registry.dart';
import 'local_library_service.dart';
import 'web_proxy_helper.dart';

class ArtistService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final ProviderRegistry _registry;
  final LocalLibraryService? _libraryService;
  final http.Client _client;

  List<Artist> _favoriteArtists = [];
  bool _isLoading = false;

  ArtistService({
    DatabaseHelper? dbHelper,
    required ProviderRegistry registry,
    LocalLibraryService? libraryService,
    http.Client? client,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _registry = registry,
        _libraryService = libraryService,
        _client = client ?? http.Client() {
    loadFavorites();
  }

  List<Artist> get favoriteArtists => List.unmodifiable(_favoriteArtists);
  bool get isLoading => _isLoading;

  bool isFavorite(String artistName) {
    final lower = artistName.trim().toLowerCase();
    return _favoriteArtists.any((a) => a.name.trim().toLowerCase() == lower);
  }

  Future<void> loadFavorites() async {
    try {
      _isLoading = true;
      _favoriteArtists = await _dbHelper.getFavoriteArtists();
    } catch (e) {
      if (kDebugMode) {
        print('[ArtistService] loadFavorites error: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  VoidCallback? onFavoritesChanged;

  Future<bool> toggleFavorite(Artist artist) async {
    final exists = isFavorite(artist.name);
    if (exists) {
      await _dbHelper.removeFavoriteArtist(artist.name);
      _favoriteArtists.removeWhere(
        (a) => a.name.trim().toLowerCase() == artist.name.trim().toLowerCase(),
      );
      notifyListeners();
      onFavoritesChanged?.call();
      return false;
    } else {
      final toSave = artist.copyWith(addedAt: DateTime.now());
      await _dbHelper.addFavoriteArtist(toSave);
      _favoriteArtists.removeWhere(
        (a) => a.name.trim().toLowerCase() == artist.name.trim().toLowerCase(),
      );
      _favoriteArtists.insert(0, toSave);
      notifyListeners();
      onFavoritesChanged?.call();
      return true;
    }
  }

  Future<void> mergeSyncedArtists(List<Artist> artists) async {
    for (final artist in artists) {
      if (!isFavorite(artist.name)) {
        await _dbHelper.addFavoriteArtist(artist);
      }
    }
    await loadFavorites();
  }

  Future<bool> toggleFavoriteByName(String name, {String? artworkUrl}) async {
    return await toggleFavorite(
      Artist(
        name: name.trim(),
        artworkUrl: artworkUrl,
        addedAt: DateTime.now(),
      ),
    );
  }

  List<Artist> getArtistsFromLibrary() {
    if (_libraryService == null) return [];
    final tracks = _libraryService.tracks;
    final Map<String, (int, String?)> artistMap = {};

    for (final track in tracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      final existing = artistMap[name];
      if (existing == null) {
        artistMap[name] = (1, track.artworkUrl);
      } else {
        artistMap[name] = (existing.$1 + 1, existing.$2 ?? track.artworkUrl);
      }
    }

    final list = artistMap.entries.map((e) {
      return Artist(
        name: e.key,
        artworkUrl: e.value.$2,
        addedAt: DateTime.now(),
        trackCount: e.value.$1,
        providerId: 'local',
      );
    }).toList();

    list.sort((a, b) => (b.trackCount ?? 0).compareTo(a.trackCount ?? 0));
    return list;
  }

  Future<List<Artist>> searchArtists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return _favoriteArtists;

    final results = <Artist>[];
    final seen = <String>{};

    // 1. Favorites match
    for (final fav in _favoriteArtists) {
      if (fav.name.toLowerCase().contains(cleanQuery.toLowerCase())) {
        if (seen.add(fav.name.toLowerCase())) {
          results.add(fav);
        }
      }
    }

    // 2. Local library match
    for (final libArtist in getArtistsFromLibrary()) {
      if (libArtist.name.toLowerCase().contains(cleanQuery.toLowerCase())) {
        if (seen.add(libArtist.name.toLowerCase())) {
          results.add(libArtist);
        }
      }
    }

    // 3. Online Deezer Artist Search API (High quality artist photos and fan counts)
    try {
      final uri = Uri.parse('https://api.deezer.com/search/artist').replace(
        queryParameters: {
          'q': cleanQuery,
          'limit': '15',
        },
      );
      final resp = await _client
          .get(WebProxyHelper.proxyUri(uri))
          .timeout(const Duration(milliseconds: 2500));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final list = data['data'] as List?;
        if (list != null) {
          for (final item in list) {
            final name = (item['name'] as String?)?.trim();
            if (name != null && name.isNotEmpty && seen.add(name.toLowerCase())) {
              final pic = item['picture_medium'] as String? ?? item['picture_big'] as String?;
              final nbFan = item['nb_fan'] as int?;
              results.add(
                Artist(
                  name: name,
                  artworkUrl: pic,
                  addedAt: DateTime.now(),
                  trackCount: nbFan,
                  providerId: 'deezer',
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ArtistService] Deezer artist search exception: $e');
      }
    }

    // 4. Fallback: extract artists from multi-provider track search if results are scarce
    if (results.length < 5) {
      try {
        final tracks = await _registry.searchAcrossProviders(cleanQuery);
        for (final t in tracks) {
          final name = t.artist.trim();
          if (name.isNotEmpty && seen.add(name.toLowerCase())) {
            results.add(
              Artist(
                name: name,
                artworkUrl: t.artworkUrl,
                addedAt: DateTime.now(),
                providerId: t.providerId,
              ),
            );
          }
          if (results.length >= 25) break;
        }
      } catch (_) {}
    }

    return results;
  }

  Future<List<Track>> getArtistTracks(String artistName) async {
    final clean = artistName.trim();
    if (clean.isEmpty) return [];

    final localMatches = _libraryService?.tracks.where((t) {
          return t.artist.toLowerCase().contains(clean.toLowerCase());
        }).toList() ??
        [];

    List<Track> providerMatches = [];
    try {
      providerMatches = await _registry.searchAcrossProviders(clean);
    } catch (_) {}

    final all = <Track>[...localMatches, ...providerMatches];
    final seen = <String>{};
    final unique = <Track>[];

    for (final t in all) {
      final key = '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
      if (seen.add(key)) {
        unique.add(t);
      }
    }

    // Prioritize tracks where artist matches closely
    unique.sort((a, b) {
      final aExact = a.artist.trim().toLowerCase() == clean.toLowerCase();
      final bExact = b.artist.trim().toLowerCase() == clean.toLowerCase();
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      return 0;
    });

    return unique;
  }
}
