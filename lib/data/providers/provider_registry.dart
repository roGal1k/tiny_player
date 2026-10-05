import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';
import 'hitmo_provider.dart';

class ProviderRegistry {
  final List<MusicProvider> _providers = [];
  final Set<String> _disabledProviderIds = {};

  void registerProvider(MusicProvider provider) {
    _providers.add(provider);
  }

  void removeProvider(String providerId) {
    _providers.removeWhere((p) => p.providerId == providerId);
  }

  void setProviderEnabled(String providerId, bool enabled) {
    if (enabled) {
      _disabledProviderIds.remove(providerId.toLowerCase());
    } else {
      _disabledProviderIds.add(providerId.toLowerCase());
    }
  }

  bool isProviderEnabled(String providerId) {
    return !_disabledProviderIds.contains(providerId.toLowerCase());
  }

  void syncDisabledProviders(Set<String> disabled) {
    _disabledProviderIds.clear();
    _disabledProviderIds.addAll(disabled.map((e) => e.toLowerCase()));
  }

  List<MusicProvider> get allProviders => List.unmodifiable(_providers);

  List<MusicProvider> get activeProviders => List.unmodifiable(
      _providers.where((p) => isProviderEnabled(p.providerId)));

  /// Performs a meta-search across all registered and enabled providers
  /// and merges the results.
  Future<List<Track>> searchAcrossProviders(String query, {Map<String, dynamic>? filters}) async {
    final searchFutures = activeProviders.map((provider) async {
      final stopwatch = Stopwatch()..start();
      try {
        final results = await provider.search(query, filters: filters);
        stopwatch.stop();
        print('[${provider.name}] Search took ${stopwatch.elapsedMilliseconds}ms. Found ${results.length} tracks.');
        return results;
      } catch (e) {
        stopwatch.stop();
        print('[${provider.name}] Search failed after ${stopwatch.elapsedMilliseconds}ms: $e');
        return <Track>[]; // Return empty list on failure for a single provider
      }
    });

    // Wait for all providers to finish searching
    final results = await Future.wait(searchFutures);

    // Interleave results round-robin so top tracks from all providers appear first
    final allTracks = _interleaveTracks(results);

    return allTracks;
  }

  static List<Track> _interleaveTracks(List<List<Track>> providerResults) {
    final interleaved = <Track>[];
    int maxLen = 0;
    for (final list in providerResults) {
      if (list.length > maxLen) maxLen = list.length;
    }
    for (int i = 0; i < maxLen; i++) {
      for (final list in providerResults) {
        if (i < list.length) {
          interleaved.add(list[i]);
        }
      }
    }
    return interleaved;
  }

  /// Получает популярные треки/чарты сегодняшнего дня
  Future<List<Track>> getPopularTracks() async {
    final results = <Track>[];
    for (final provider in _providers) {
      if (provider is HitmoProvider && isProviderEnabled(provider.providerId)) {
        try {
          final tracks = await provider.getPopularTracks();
          results.addAll(tracks);
        } catch (e) {
          print('[HitmoProvider] getPopularTracks error: $e');
        }
      }
    }

    if (results.isEmpty) {
      return searchAcrossProviders('Top Hits 2024');
    }
    return results;
  }

  /// Получает музыкальные новинки
  Future<List<Track>> getNewReleases() async {
    final results = <Track>[];
    for (final provider in _providers) {
      if (provider is HitmoProvider && isProviderEnabled(provider.providerId)) {
        try {
          final tracks = await provider.getNewTracks();
          results.addAll(tracks);
        } catch (e) {
          print('[HitmoProvider] getNewTracks error: $e');
        }
      }
    }

    if (results.isEmpty) {
      return searchAcrossProviders('New Music');
    }
    return results;
  }

  /// Получает треки по жанру/подборке
  Future<List<Track>> getTracksByGenre(String genre) async {
    return searchAcrossProviders(genre);
  }
}

