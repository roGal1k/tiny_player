import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/audio_cache_service.dart';
import 'package:core_player/data/services/download_manager.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/presentation/screens/downloads_screen.dart';

class FakeLocalLibraryService extends ChangeNotifier implements LocalLibraryService {
  final List<Track> _tracks;
  FakeLocalLibraryService(this._tracks);

  @override
  List<Track> get tracks => _tracks;

  @override
  bool get isScanning => false;

  @override
  String? get statusMessage => null;

  @override
  Future<void> loadLibrary() async {}

  @override
  Future<void> removeTrack(String trackId) async {
    _tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
  }

  @override
  Future<int> scanDirectory(String directoryPath) async => 0;
}

void main() {
  testWidgets('renders empty state when no tracks in library or download tasks', (tester) async {
    final registry = ProviderRegistry();
    final libraryService = FakeLocalLibraryService([]);
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );
    final audioController = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
          ChangeNotifierProvider<AudioCacheService?>.value(value: null),
        ],
        child: const MaterialApp(
          home: DownloadsScreen(),
        ),
      ),
    );

    expect(find.text('Загрузки'), findsOneWidget);
    expect(find.text('Нет скачанных треков'), findsOneWidget);

    audioController.dispose();
  });

  testWidgets('renders downloaded tracks with duration in Tab 1', (tester) async {
    final registry = ProviderRegistry();
    final downloadedTrack = Track(
      id: 'local_1',
      providerId: 'local',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      duration: const Duration(minutes: 5, seconds: 55),
      isStreamable: true,
      isDownloadable: false,
      sourceUrl: '/home/gera/Music/CorePlayer/Queen - Bohemian Rhapsody.mp3',
    );

    final libraryService = FakeLocalLibraryService([downloadedTrack]);
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );
    final audioController = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
          ChangeNotifierProvider<AudioCacheService?>.value(value: null),
        ],
        child: const MaterialApp(
          home: DownloadsScreen(),
        ),
      ),
    );

    expect(find.text('Загрузки (1)'), findsOneWidget);
    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
    expect(find.text('СКАЧАНО'), findsOneWidget);
    expect(find.text('Слушать все'), findsOneWidget);
    // Verifies duration display (05:55)
    expect(find.text('05:55'), findsOneWidget);

    audioController.dispose();
  });
}
