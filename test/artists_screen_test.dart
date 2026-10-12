import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/domain/models/artist.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/data/services/artist_service.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:core_player/presentation/screens/artists_screen.dart';
import 'package:core_player/presentation/screens/artist_detail_screen.dart';
import 'fake_audioplayers.dart';

class FakeLocalLibraryService extends ChangeNotifier implements LocalLibraryService {
  final List<Track> _tracks;
  FakeLocalLibraryService([this._tracks = const []]);

  @override
  List<Track> get tracks => _tracks;

  @override
  bool get isScanning => false;

  @override
  String? get statusMessage => null;

  @override
  Future<void> loadLibrary() async {}

  @override
  Future<void> removeTrack(String trackId) async {}

  @override
  Future<int> scanDirectory(String directoryPath) async => 0;

  @override
  bool isFavorite(String trackId) => false;

  @override
  Future<bool> toggleFavorite(Track track) async => false;
}

class FakeArtistService extends ChangeNotifier implements ArtistService {
  final Map<String, Artist> _favs = {};
  final List<Track> _tracks = [];
  bool _searching = false;

  FakeArtistService({List<Artist>? initialFavorites, List<Track>? mockTracks}) {
    if (initialFavorites != null) {
      for (final a in initialFavorites) {
        _favs[a.name.toLowerCase().trim()] = a;
      }
    }
    if (mockTracks != null) {
      _tracks.addAll(mockTracks);
    }
  }

  @override
  List<Artist> get favoriteArtists => _favs.values.toList();

  @override
  bool get isSearching => _searching;

  @override
  String? get lastError => null;

  @override
  bool isFavorite(String artistName) => _favs.containsKey(artistName.toLowerCase().trim());

  @override
  Future<bool> toggleFavorite(Artist artist) async {
    final key = artist.name.toLowerCase().trim();
    if (_favs.containsKey(key)) {
      _favs.remove(key);
      notifyListeners();
      return false;
    } else {
      _favs[key] = artist;
      notifyListeners();
      return true;
    }
  }

  @override
  bool get isLoading => false;

  @override
  Future<bool> toggleFavoriteByName(String artistName, {String? artworkUrl, String? providerId}) async {
    return toggleFavorite(Artist(
      name: artistName,
      artworkUrl: artworkUrl,
      providerId: providerId,
      addedAt: DateTime.now(),
    ));
  }

  @override
  Future<void> loadFavorites() async {}

  @override
  List<Artist> getArtistsFromLibrary() => [];

  @override
  Future<List<Artist>> searchArtists(String query) async => [];

  @override
  Future<List<Track>> getArtistTracks(String artistName) async {
    return _tracks.where((t) => t.artist.toLowerCase() == artistName.toLowerCase()).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioplayersPlatformInterface.instance = FakeAudioplayersPlatform();
  GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioplayersPlatform();

  group('ArtistsScreen Widget Tests', () {
    late ProviderRegistry registry;
    late FakeArtistService artistService;
    late FakeLocalLibraryService libraryService;
    late DownloadManager downloadManager;
    late AudioPlayerController audioController;

    setUp(() {
      registry = ProviderRegistry();
      libraryService = FakeLocalLibraryService([]);
      artistService = FakeArtistService();
      downloadManager = DownloadManager(
        registry: registry,
        libraryService: libraryService,
      );
      audioController = AudioPlayerController(registry: registry);
    });

    tearDown(() {
      audioController.dispose();
    });

    Widget createTestApp(Widget child) {
      return MultiProvider(
        providers: [
          Provider<ProviderRegistry>.value(value: registry),
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<ArtistService>.value(value: artistService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('ArtistsScreen renders title, search bar, and empty state', (tester) async {
      await tester.pumpWidget(createTestApp(const ArtistsScreen()));
      await tester.pump();

      expect(find.text('Исполнители'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Нет избранных исполнителей'), findsOneWidget);
      expect(find.textContaining('Избранные (0)'), findsOneWidget);
      expect(find.textContaining('Из медиатеки (0)'), findsOneWidget);
    });

    testWidgets('ArtistsScreen displays favorite artists and toggles heart icon', (tester) async {
      final testArtist = Artist(
        name: 'The Beatles',
        artworkUrl: null,
        addedAt: DateTime.now(),
      );
      await artistService.toggleFavorite(testArtist);

      await tester.pumpWidget(createTestApp(const ArtistsScreen()));
      await tester.pump();

      expect(find.text('The Beatles'), findsOneWidget);
      expect(find.textContaining('Избранные (1)'), findsOneWidget);

      // Tap favorite heart to remove
      final heartBtn = find.byIcon(Icons.favorite).first;
      await tester.tap(heartBtn);
      await tester.pump();

      expect(artistService.isFavorite('The Beatles'), isFalse);
    });

    testWidgets('ArtistDetailScreen renders artist header and action buttons', (tester) async {
      final testArtist = Artist(
        name: 'Linkin Park',
        artworkUrl: null,
        addedAt: DateTime.now(),
        trackCount: 12,
      );

      await tester.pumpWidget(createTestApp(ArtistDetailScreen(artist: testArtist)));
      await tester.pump();

      expect(find.text('Linkin Park'), findsWidgets);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Toggle favorite on detail screen
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(artistService.isFavorite('Linkin Park'), isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('ArtistDetailScreen filters tracks by source provider chips', (tester) async {
      final mockTracks = [
        Track(
          id: '1',
          title: 'Numb',
          artist: 'Linkin Park',
          album: 'Meteora',
          duration: const Duration(seconds: 185),
          sourceUrl: 'http://hitmo/1.mp3',
          providerId: 'hitmo',
        ),
        Track(
          id: '2',
          title: 'In The End',
          artist: 'Linkin Park',
          album: 'Hybrid Theory',
          duration: const Duration(seconds: 216),
          sourceUrl: 'http://youtube/2.mp3',
          providerId: 'youtube',
        ),
        Track(
          id: '3',
          title: 'Faint',
          artist: 'Linkin Park',
          album: 'Meteora',
          duration: const Duration(seconds: 162),
          sourceUrl: 'http://hitmo/3.mp3',
          providerId: 'hitmo',
        ),
      ];

      artistService = FakeArtistService(mockTracks: mockTracks);

      final testArtist = Artist(
        name: 'Linkin Park',
        artworkUrl: null,
        addedAt: DateTime.now(),
      );

      await tester.pumpWidget(createTestApp(ArtistDetailScreen(artist: testArtist)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should show provider filter chips: "Все (3)", "Hitmo (2)", "YouTube (1)"
      expect(find.text('Все (3)'), findsOneWidget);
      expect(find.text('Hitmo (2)'), findsOneWidget);
      expect(find.text('YouTube (1)'), findsOneWidget);

      // Initially all 3 tracks displayed
      expect(find.text('Numb'), findsOneWidget);
      expect(find.text('In The End'), findsOneWidget);
      expect(find.text('Faint'), findsOneWidget);
      expect(find.text('Слушать всё (3)'), findsOneWidget);

      // Tap Hitmo chip
      await tester.tap(find.text('Hitmo (2)'));
      await tester.pumpAndSettle();

      // Only Hitmo tracks should be shown
      expect(find.text('Numb'), findsOneWidget);
      expect(find.text('Faint'), findsOneWidget);
      expect(find.text('In The End'), findsNothing);
      expect(find.text('Слушать всё (2)'), findsOneWidget);

      // Tap YouTube chip
      await tester.tap(find.text('YouTube (1)'));
      await tester.pumpAndSettle();

      expect(find.text('In The End'), findsOneWidget);
      expect(find.text('Numb'), findsNothing);
      expect(find.text('Faint'), findsNothing);
      expect(find.text('Слушать всё (1)'), findsOneWidget);
    });
  });
}
