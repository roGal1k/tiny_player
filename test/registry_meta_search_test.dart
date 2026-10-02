import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/providers/hitmo_provider.dart';
import 'package:core_player/data/providers/youtube_provider.dart';

void main() {
  test('Meta-search across providers with Hitmo and YouTube', () async {
    final registry = ProviderRegistry();
    final hitmo = HitmoProvider(mirrorUrl: 'https://ru.hitmoz.org');
    final yt = YouTubeProvider();

    registry.registerProvider(hitmo);
    registry.registerProvider(yt);

    print('Active providers: ${registry.activeProviders.map((p) => p.name).toList()}');

    for (final q in ['Queen', 'Rammstein', 'Кино', 'Miyagi']) {
      print('\n--- Searching "$q" ---');
      final results = await registry.searchAcrossProviders(q);
      final hitmoTracks = results.where((t) => t.providerId == 'hitmo').toList();
      final ytTracks = results.where((t) => t.providerId == 'youtube').toList();

      print('Total results: ${results.length}');
      print('Hitmo results: ${hitmoTracks.length}');
      print('YouTube results: ${ytTracks.length}');

      if (hitmoTracks.isNotEmpty) {
        print('Sample Hitmo: "${hitmoTracks.first.title}" by "${hitmoTracks.first.artist}"');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
