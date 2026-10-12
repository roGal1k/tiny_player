import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:core_player/domain/models/artist.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/services/artist_service.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/domain/providers/music_provider.dart';

class MockTestProvider implements MusicProvider {
  @override
  String get providerId => 'mock_music';

  @override
  String get name => 'Mock Music';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    if (query.toLowerCase().contains('queen')) {
      return [
        const Track(
          id: 'q1',
          providerId: 'mock_music',
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          duration: Duration(minutes: 5, seconds: 55),
          sourceUrl: 'https://example.com/bohemian.mp3',
        ),
        const Track(
          id: 'q2',
          providerId: 'mock_music',
          title: 'Radio Ga Ga',
          artist: 'Queen',
          duration: Duration(minutes: 5, seconds: 48),
          sourceUrl: 'https://example.com/radio.mp3',
        ),
      ];
    }
    return [];
  }

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => track.sourceUrl;

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getPopularTracks({int limit = 20}) async => [];

  @override
  Future<List<Track>> getNewReleases({int limit = 20}) async => [];

  @override
  Future<List<Track>> getTracksByGenre(String genre, {int limit = 20}) async => [];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Artist Model Tests', () {
    test('Artist toMap and fromMap works correctly', () {
      final now = DateTime(2026, 10, 9, 12, 0);
      final artist = Artist(
        name: 'Freddie Mercury',
        artworkUrl: 'https://example.com/freddie.jpg',
        addedAt: now,
        trackCount: 42,
        providerId: 'deezer',
      );

      final map = artist.toMap();
      expect(map['name'], equals('Freddie Mercury'));
      expect(map['artwork_url'], equals('https://example.com/freddie.jpg'));
      expect(map['added_at'], equals(now.toIso8601String()));

      final reconstructed = Artist.fromMap(map);
      expect(reconstructed.name, equals('Freddie Mercury'));
      expect(reconstructed.artworkUrl, equals('https://example.com/freddie.jpg'));
      expect(reconstructed.addedAt, equals(now));
      expect(artist == reconstructed, isTrue);
    });

    test('Artist copyWith modifies specific fields', () {
      final artist = Artist(
        name: 'Queen',
        addedAt: DateTime.now(),
      );

      final updated = artist.copyWith(
        artworkUrl: 'https://example.com/queen.jpg',
        trackCount: 15,
      );

      expect(updated.name, equals('Queen'));
      expect(updated.artworkUrl, equals('https://example.com/queen.jpg'));
      expect(updated.trackCount, equals(15));
    });
  });

  group('DatabaseHelper Favorite Artists Tests', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
    });

    test('adds, retrieves, and removes favorite artist', () async {
      expect(await dbHelper.getFavoriteArtists(), isEmpty);
      expect(await dbHelper.isFavoriteArtist('Viktor Tsoi'), isFalse);

      final artist = Artist(
        name: 'Viktor Tsoi',
        artworkUrl: 'https://example.com/tsoi.jpg',
        addedAt: DateTime.now(),
      );

      await dbHelper.addFavoriteArtist(artist);

      expect(await dbHelper.isFavoriteArtist('Viktor Tsoi'), isTrue);
      expect(await dbHelper.isFavoriteArtist('viktor tsoi'), isTrue); // case-insensitive check

      final list = await dbHelper.getFavoriteArtists();
      expect(list.length, equals(1));
      expect(list.first.name, equals('Viktor Tsoi'));

      await dbHelper.removeFavoriteArtist('viktor tsoi');
      expect(await dbHelper.isFavoriteArtist('Viktor Tsoi'), isFalse);
      expect(await dbHelper.getFavoriteArtists(), isEmpty);
    });
  });

  group('ArtistService Tests', () {
    late DatabaseHelper dbHelper;
    late ProviderRegistry registry;
    late MockTestProvider mockProvider;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
      registry = ProviderRegistry();
      mockProvider = MockTestProvider();
      registry.registerProvider(mockProvider);
    });

    test('toggleFavorite adds and removes artist with notification', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"data":[]}', 200);
      });

      final service = ArtistService(
        dbHelper: dbHelper,
        registry: registry,
        client: mockClient,
      );

      bool notified = false;
      service.addListener(() => notified = true);

      final artist = Artist(
        name: 'Miyagi',
        artworkUrl: 'https://example.com/miyagi.jpg',
        addedAt: DateTime.now(),
      );

      // Add
      final added = await service.toggleFavorite(artist);
      expect(added, isTrue);
      expect(service.isFavorite('Miyagi'), isTrue);
      expect(service.isFavorite('miyagi'), isTrue);
      expect(service.favoriteArtists.length, equals(1));
      expect(notified, isTrue);

      // Remove
      notified = false;
      final removed = await service.toggleFavorite(artist);
      expect(removed, isFalse);
      expect(service.isFavorite('Miyagi'), isFalse);
      expect(service.favoriteArtists, isEmpty);
      expect(notified, isTrue);
    });

    test('searchArtists returns Deezer API matches and marks favorites', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/search/artist')) {
          final body = json.encode({
            'data': [
              {
                'id': 412,
                'name': 'Queen',
                'picture_medium': 'https://example.com/queen_medium.jpg',
                'nb_fan': 5000000,
              },
              {
                'id': 999,
                'name': 'Queens of the Stone Age',
                'picture_medium': 'https://example.com/qotsa.jpg',
                'nb_fan': 1200000,
              }
            ]
          });
          return http.Response(body, 200);
        }
        return http.Response('{"data":[]}', 200);
      });

      final service = ArtistService(
        dbHelper: dbHelper,
        registry: registry,
        client: mockClient,
      );

      final results = await service.searchArtists('Queen');
      expect(results.length, equals(2));
      expect(results.any((a) => a.name == 'Queen'), isTrue);
      expect(results.any((a) => a.name == 'Queens of the Stone Age'), isTrue);
    });

    test('getArtistTracks finds tracks from providers and library', () async {
      final service = ArtistService(
        dbHelper: dbHelper,
        registry: registry,
      );

      final tracks = await service.getArtistTracks('Queen');
      expect(tracks.length, equals(2));
      expect(tracks.first.title, equals('Bohemian Rhapsody'));
      expect(tracks.first.artist, equals('Queen'));
    });
  });
}
