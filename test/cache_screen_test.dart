import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/audio_cache_service.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/presentation/screens/cache_screen.dart';

class FakeAudioCacheService extends ChangeNotifier implements AudioCacheService {
  final List<Track> _tracks;
  FakeAudioCacheService(this._tracks);

  @override
  String get cacheDir => '/tmp/fake_cache';

  @override
  int get cachedCount => _tracks.length;

  @override
  int get totalCacheSizeBytes => 4500000;

  @override
  Future<List<Track>> getCachedTracks() async => List.unmodifiable(_tracks);

  @override
  bool isCached(Track track) => _tracks.any((t) => t.id == track.id);

  @override
  File? getCachedFile(Track track) => null;

  @override
  Future<void> removeTrackFromCache(Track track) async {
    _tracks.removeWhere((t) => t.id == track.id);
    notifyListeners();
  }

  @override
  Future<void> clearCache() async {
    _tracks.clear();
    notifyListeners();
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> preloadTrack(Track track, MusicProvider provider) async {}

  @override
  Future<File?> cacheTrackInBackground(Track track, String streamUrl) async => null;

  @override
  Future<void> registerExistingLocalFile(Track track, String localPath) async {}

  @override
  String formatBytes(int bytes) => '4.3 MB';
}

void main() {
  testWidgets('CacheScreen displays empty state when no tracks cached', (tester) async {
    final registry = ProviderRegistry();
    final audioController = AudioPlayerController(registry: registry);
    final cacheService = FakeAudioCacheService([]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
          ChangeNotifierProvider<AudioCacheService?>.value(value: cacheService),
        ],
        child: const MaterialApp(
          home: CacheScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Офлайн-кэш'), findsOneWidget);
    expect(find.text('Офлайн-кэш пуст'), findsOneWidget);
    expect(find.byIcon(Icons.offline_pin_outlined), findsOneWidget);

    audioController.dispose();
  });

  testWidgets('CacheScreen displays cached tracks with duration, stats and play all', (tester) async {
    final registry = ProviderRegistry();
    final audioController = AudioPlayerController(registry: registry);
    final cachedTrack = Track(
      id: 'cache_track_1',
      providerId: 'hitmo',
      title: 'Кукла колдуна',
      artist: 'Король и Шут',
      album: 'Акустический альбом',
      duration: const Duration(minutes: 3, seconds: 24),
      isStreamable: true,
      isDownloadable: true,
      sourceUrl: '/tmp/fake_cache/hitmo_cache_track_1.mp3',
    );
    final cacheService = FakeAudioCacheService([cachedTrack]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerController>.value(value: audioController),
          ChangeNotifierProvider<AudioCacheService?>.value(value: cacheService),
        ],
        child: const MaterialApp(
          home: CacheScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Stats banner
    expect(find.text('Офлайн-кэш'), findsOneWidget);
    expect(find.text('1 закэшированных треков'), findsOneWidget);
    expect(find.text('Слушать все'), findsOneWidget);

    // Verify Track info & duration
    expect(find.text('Кукла колдуна'), findsOneWidget);
    expect(find.text('Король и Шут'), findsOneWidget);
    expect(find.text('HITMO'), findsOneWidget);
    expect(find.text('03:24'), findsOneWidget);

    // Verify search filter in cache
    await tester.enterText(find.byType(TextField), 'Король');
    await tester.pumpAndSettle();
    expect(find.text('Кукла колдуна'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'NonExistent');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено по запросу "NonExistent"'), findsOneWidget);

    audioController.dispose();
  });
}
