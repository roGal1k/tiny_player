import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core_player/data/providers/audius_provider.dart';
import 'package:core_player/domain/models/track.dart';

void main() {
  group('AudiusProvider Unit Tests', () {
    test('metadata properties are correct', () async {
      final provider = AudiusProvider();
      expect(provider.providerId, equals('audius'));
      expect(provider.name, equals('Audius'));
      expect(await provider.authenticate(), isTrue);
      expect(await provider.getUserLibrary(), isEmpty);
    });

    test('search returns empty list for empty query', () async {
      final provider = AudiusProvider();
      final results = await provider.search('   ');
      expect(results, isEmpty);
    });

    test('search parses tracks from API response correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/tracks/search'));
        expect(request.url.queryParameters['query'], equals('electronic'));
        expect(request.url.queryParameters['app_name'], equals('CorePlayer'));

        final responseData = {
          'data': [
            {
              'id': 'D7KyZ',
              'title': 'Neon Dreams',
              'user': {
                'name': 'Synth Master',
                'handle': 'synthmaster',
              },
              'artwork': {
                '150x150': 'https://audius.co/art_150.jpg',
                '480x480': 'https://audius.co/art_480.jpg',
                '1000x1000': 'https://audius.co/art_1000.jpg',
              },
              'duration': 185,
              'genre': 'Electronic',
            },
            {
              'id': 'X99aQ',
              'title': 'Ambient Waves',
              'user': {
                'handle': 'ambient_producer',
              },
              'duration': 240,
            }
          ]
        };

        return http.Response(json.encode(responseData), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final provider = AudiusProvider(client: mockClient);
      final tracks = await provider.search('electronic');

      expect(tracks.length, equals(2));

      final first = tracks[0];
      expect(first.id, equals('D7KyZ'));
      expect(first.providerId, equals('audius'));
      expect(first.title, equals('Neon Dreams'));
      expect(first.artist, equals('Synth Master'));
      expect(first.artworkUrl, equals('https://audius.co/art_480.jpg'));
      expect(first.duration.inSeconds, equals(185));
      expect(first.genre, equals('Electronic'));
      expect(first.isStreamable, isTrue);
      expect(first.isDownloadable, isTrue);
      expect(first.sourceUrl, contains('/tracks/D7KyZ/stream?app_name=CorePlayer'));

      final second = tracks[1];
      expect(second.id, equals('X99aQ'));
      expect(second.artist, equals('ambient_producer'));
      expect(second.artworkUrl, isNull);
      expect(second.duration.inSeconds, equals(240));
    });

    test('getTrack parses single track response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/tracks/D7KyZ'));
        final responseData = {
          'data': {
            'id': 'D7KyZ',
            'title': 'Neon Dreams',
            'user': {'name': 'Synth Master'},
            'duration': 185,
          }
        };
        return http.Response(json.encode(responseData), 200);
      });

      final provider = AudiusProvider(client: mockClient);
      final track = await provider.getTrack('D7KyZ');

      expect(track, isNotNull);
      expect(track!.id, equals('D7KyZ'));
      expect(track.title, equals('Neon Dreams'));
    });

    test('getTrack handles missing track gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final provider = AudiusProvider(client: mockClient);
      final track = await provider.getTrack('non_existent');
      expect(track, isNull);
    });

    test('getStreamUrl and getDownloadOptions work as expected', () async {
      final provider = AudiusProvider();
      final track = Track(
        id: '12345',
        providerId: 'audius',
        title: 'Test',
        artist: 'Test Artist',
        duration: const Duration(seconds: 120),
        sourceUrl: 'https://discoveryprovider.audius.co/v1/tracks/12345/stream?app_name=CorePlayer',
      );

      final streamUrl = await provider.getStreamUrl(track);
      expect(streamUrl, equals(track.sourceUrl));

      final downloadOptions = await provider.getDownloadOptions(track);
      expect(downloadOptions, equals(['mp3']));
    });
  });
}
