import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/providers/hitmo_provider.dart';
import 'package:core_player/data/services/full_track_resolver.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MockDeezerProvider implements MusicProvider {
  @override
  String get providerId => 'deezer';

  @override
  String get name => 'Deezer';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async => [];

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => 'https://cdns-preview-d.dzcdn.net/preview.mp3';

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

void main() {
  group('FullTrackResolver Tests', () {
    late ProviderRegistry registry;
    late FullTrackResolver resolver;

    setUp(() {
      registry = ProviderRegistry();
      registry.registerProvider(MockDeezerProvider());
      resolver = FullTrackResolver(registry: registry);
    });

    test('isPreviewTrack identifies Deezer tracks and preview URLs', () {
      final deezerTrack = Track(
        id: '123',
        providerId: 'deezer',
        title: 'Song',
        artist: 'Artist',
        duration: const Duration(seconds: 180),
        sourceUrl: 'https://cdns-preview-d.dzcdn.net/preview.mp3',
      );

      final normalTrack = Track(
        id: '456',
        providerId: 'hitmo',
        title: 'Song',
        artist: 'Artist',
        duration: const Duration(seconds: 180),
        sourceUrl: 'https://hitmo.org/song.mp3',
      );

      expect(resolver.isPreviewTrack(deezerTrack), isTrue);
      expect(resolver.isPreviewTrack(normalTrack), isFalse);
    });

    test('resolveStream resolves full track from Hitmo when available for Deezer preview', () async {
      // Mock Hitmo client returning HTML with exact classes expected by parser
      final mockHitmoHtml = '''
      <html>
        <body>
          <div class="tracks__item">
            <div class="track__info">
              <div class="track__title">My Song</div>
              <div class="track__desc">My Artist</div>
              <div class="track__fulltime">3:45</div>
              <a class="track__download-btn" href="/get/music/2026/my_song.mp3"></a>
            </div>
          </div>
        </body>
      </html>
      ''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/search') || request.url.path.contains('/get/music')) {
          return http.Response(mockHitmoHtml, 200);
        }
        return http.Response('', 200);
      });

      final hitmo = HitmoProvider(client: mockClient, mirrorUrl: 'https://ru.hitmoz.org');
      registry.registerProvider(hitmo);

      final deezerTrack = Track(
        id: 'dz_1',
        providerId: 'deezer',
        title: 'My Song',
        artist: 'My Artist',
        duration: const Duration(seconds: 180),
        sourceUrl: 'https://cdns-preview-d.dzcdn.net/preview.mp3',
      );

      final resolved = await resolver.resolveStream(deezerTrack);
      expect(resolved.isFullLength, isTrue);
      expect(resolved.effectiveSource, equals('hitmo'));
      expect(resolved.streamUrl, contains('my_song.mp3'));
    });

    test('resolveStream falls back to preview if no full track is found', () async {
      final deezerTrack = Track(
        id: 'dz_2',
        providerId: 'deezer',
        title: 'Obscure Track',
        artist: 'Unknown Artist',
        duration: const Duration(seconds: 180),
        sourceUrl: 'https://cdns-preview-d.dzcdn.net/preview.mp3',
      );

      final resolved = await resolver.resolveStream(deezerTrack);
      expect(resolved.isFullLength, isFalse);
      expect(resolved.streamUrl, equals('https://cdns-preview-d.dzcdn.net/preview.mp3'));
    });
  });
}
