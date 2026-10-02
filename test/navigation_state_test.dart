import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/main.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';

class _MockNavigationProvider implements MusicProvider {
  int searchCallCount = 0;

  @override
  String get providerId => 'mock_nav';

  @override
  String get name => 'MockNav';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    searchCallCount++;
    return [
      Track(
        id: 'nav_track_1',
        providerId: providerId,
        title: '$query Special Track',
        artist: 'Test Artist',
        duration: const Duration(minutes: 3),
        isStreamable: true,
        isDownloadable: true,
        sourceUrl: 'https://example.com/stream.mp3',
      ),
    ];
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
  testWidgets('SearchScreen preserves search query, results and state when navigating between tabs', (tester) async {
    final mockProvider = _MockNavigationProvider();
    final registry = ProviderRegistry();
    registry.registerProvider(mockProvider);

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
          home: MainLayout(),
        ),
      ),
    );

    // Initial tab: Home
    expect(find.text('Scan Folder'), findsOneWidget);

    // Switch to Search tab (index 1)
    await tester.tap(find.byIcon(Icons.search_outlined).first);
    await tester.pumpAndSettle();

    // Perform a search
    await tester.enterText(find.byType(TextField), 'Bohemian Rhapsody');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Verify search results appear
    expect(find.text('Bohemian Rhapsody Special Track'), findsOneWidget);
    expect(mockProvider.searchCallCount, equals(1));

    // Switch to Downloads tab (index 3)
    await tester.tap(find.byIcon(Icons.download_outlined).first);
    await tester.pumpAndSettle();

    // Verify Downloads screen is now visible
    expect(find.text('Downloads'), findsWidgets);

    // Switch BACK to Search tab (index 1)
    await tester.tap(find.byIcon(Icons.search_outlined).first);
    await tester.pumpAndSettle();

    // Verify that the search input still contains 'Bohemian Rhapsody'
    expect(find.text('Bohemian Rhapsody'), findsOneWidget);

    // Verify that the search results are STILL rendered without a new search call
    expect(find.text('Bohemian Rhapsody Special Track'), findsOneWidget);
    expect(mockProvider.searchCallCount, equals(1));

    audioController.dispose();
  });
}
