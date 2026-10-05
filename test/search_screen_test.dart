import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/presentation/screens/search_screen.dart';

class MockSearchProvider implements MusicProvider {
  @override
  String get providerId => 'mock';

  @override
  String get name => 'MockProvider';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    return List.generate(
      12,
      (i) => Track(
        id: 'track_$i',
        providerId: 'mock',
        title: '$query Track $i',
        artist: 'Artist $i',
        duration: const Duration(minutes: 3),
        isStreamable: true,
        isDownloadable: true,
        sourceUrl: 'https://example.com/$i.mp3',
      ),
    );
  }

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => track.sourceUrl;

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

void main() {
  testWidgets('renders search screen and category chips', (tester) async {
    final registry = ProviderRegistry();
    final libraryService = LocalLibraryService();
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );
    final audioController = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProviderRegistry>.value(value: registry),
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Топ Сегодня'), findsWidgets);
    expect(find.text('Новинки'), findsWidgets);
    expect(find.text('SoundCloud'), findsWidgets);
    expect(find.text('Чарты и Рекомендации'), findsOneWidget);

    audioController.dispose();
  });

  testWidgets('tapping category loads tracks and displays batch download toolbar', (tester) async {
    final registry = ProviderRegistry();
    registry.registerProvider(MockSearchProvider());

    final libraryService = LocalLibraryService();
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );
    final audioController = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProviderRegistry>.value(value: registry),
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    // Tap on category chip "Новинки"
    await tester.tap(find.text('Новинки').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify batch download buttons and provider chips appear (Все, Топ 5, Топ 10)
    expect(find.textContaining('Все ('), findsWidgets);
    expect(find.text('Топ 5'), findsOneWidget);
    expect(find.text('Топ 10'), findsOneWidget);

    // Verify tracks are rendered
    expect(find.textContaining('Track 0'), findsOneWidget);
    // Verify track duration is rendered
    expect(find.text('03:00'), findsWidgets);

    audioController.dispose();
  });

  testWidgets('displays provider filter chips and filters by provider when multiple providers return results', (tester) async {
    final registry = ProviderRegistry();
    registry.registerProvider(MockSearchProvider());
    registry.registerProvider(_SecondMockProvider());

    final libraryService = LocalLibraryService();
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );
    final audioController = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProviderRegistry>.value(value: registry),
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Новинки').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Both providers returned tracks, so filter chips should appear
    expect(find.textContaining('Все ('), findsWidgets);
    expect(find.textContaining('Hitmo ('), findsOneWidget);

    // Tap on Hitmo filter chip
    await tester.tap(find.textContaining('Hitmo ('));
    await tester.pumpAndSettle();

    // Verify only Hitmo tracks are displayed
    expect(find.textContaining('Hitmo Track'), findsWidgets);

    audioController.dispose();
  });
}

class _SecondMockProvider implements MusicProvider {
  @override
  String get providerId => 'hitmo';

  @override
  String get name => 'Hitmo';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    return List.generate(
      4,
      (i) => Track(
        id: 'hitmo_$i',
        providerId: 'hitmo',
        title: 'Hitmo Track $i',
        artist: 'Hitmo Artist $i',
        duration: const Duration(minutes: 3),
        isStreamable: true,
        isDownloadable: true,
        sourceUrl: 'https://example.com/hitmo_$i.mp3',
      ),
    );
  }

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => track.sourceUrl;

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}
