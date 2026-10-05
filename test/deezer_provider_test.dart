import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core_player/data/providers/deezer_provider.dart';
import 'package:core_player/domain/models/track.dart';

void main() {
  group('DeezerProvider Unit Tests', () {
    test('metadata properties are correct', () async {
      final provider = DeezerProvider();
      expect(provider.providerId, equals('deezer'));
      expect(provider.name, equals('Deezer'));
      expect(await provider.authenticate(), isTrue);
      expect(await provider.getUserLibrary(), isEmpty);
    });

    test('search returns empty list for empty query', () async {
      final provider = DeezerProvider();
      final results = await provider.search('   ');
      expect(results, isEmpty);
    });

    test('search parses tracks from Deezer API response correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/search'));
        expect(request.url.queryParameters['q'], equals('daft punk'));

        final responseData = {
          'data': [
            {
              'id': 3135556,
              'title': 'Harder, Better, Faster, Stronger',
              'artist': {
                'id': 27,
                'name': 'Daft Punk',
                'picture_medium': 'https://api.deezer.com/artist/27/image',
              },
              'album': {
                'id': 302127,
                'title': 'Discovery',
                'cover_medium': 'https://e-cdns-images.dzcdn.net/images/cover/medium.jpg',
                'cover_big': 'https://e-cdns-images.dzcdn.net/images/cover/big.jpg',
              },
              'duration': 224,
              'explicit_lyrics': false,
              'preview': 'https://cdns-preview-d.dzcdn.net/stream/c-d.mp3',
            }
          ]
        };

        return http.Response(json.encode(responseData), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final provider = DeezerProvider(client: mockClient);
      final tracks = await provider.search('daft punk');

      expect(tracks.length, equals(1));
      final track = tracks.first;

      expect(track.id, equals('3135556'));
      expect(track.providerId, equals('deezer'));
      expect(track.title, equals('Harder, Better, Faster, Stronger'));
      expect(track.artist, equals('Daft Punk'));
      expect(track.album, equals('Discovery'));
      expect(track.artworkUrl, equals('https://e-cdns-images.dzcdn.net/images/cover/big.jpg'));
      expect(track.duration.inSeconds, equals(224));
      expect(track.isExplicit, isFalse);
      expect(track.isStreamable, isTrue);
      expect(track.isDownloadable, isTrue);
      expect(track.sourceUrl, equals('https://cdns-preview-d.dzcdn.net/stream/c-d.mp3'));
    });

    test('getTrack parses single track response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/track/3135556'));
        final responseData = {
          'id': 3135556,
          'title': 'Harder, Better, Faster, Stronger',
          'artist': {'name': 'Daft Punk'},
          'preview': 'https://cdns-preview-d.dzcdn.net/stream/preview.mp3',
          'duration': 224,
        };
        return http.Response(json.encode(responseData), 200);
      });

      final provider = DeezerProvider(client: mockClient);
      final track = await provider.getTrack('3135556');

      expect(track, isNotNull);
      expect(track!.id, equals('3135556'));
      expect(track.title, equals('Harder, Better, Faster, Stronger'));
      expect(track.sourceUrl, equals('https://cdns-preview-d.dzcdn.net/stream/preview.mp3'));
    });

    test('getStreamUrl returns existing sourceUrl or fetches via getTrack', () async {
      final provider = DeezerProvider();
      final track = Track(
        id: '999',
        providerId: 'deezer',
        title: 'Song',
        artist: 'Artist',
        duration: const Duration(seconds: 180),
        sourceUrl: 'https://cdns-preview.dzcdn.net/stream.mp3',
      );

      final streamUrl = await provider.getStreamUrl(track);
      expect(streamUrl, equals('https://cdns-preview.dzcdn.net/stream.mp3'));

      final downloadOptions = await provider.getDownloadOptions(track);
      expect(downloadOptions, equals(['mp3']));
    });
  });
}
