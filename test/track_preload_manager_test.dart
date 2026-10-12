import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/audio_cache_service.dart';
import 'package:core_player/data/services/settings_service.dart';
import 'package:core_player/data/services/track_preload_manager.dart';

class MockMusicProvider implements MusicProvider {
  @override
  final String providerId;
  @override
  final String name;
  final Map<String, int> streamCallCounts = {};

  MockMusicProvider(this.providerId, this.name);

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async => [];

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async {
    streamCallCounts[track.id] = (streamCallCounts[track.id] ?? 0) + 1;
    return 'http://mock/$providerId/${track.id}.mp3';
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

class FakeAudioCacheService extends AudioCacheService {
  final Set<String> cached = {};
  final List<String> cachedUrls = [];

  FakeAudioCacheService() : super(customCacheDir: Directory.systemTemp.path);

  @override
  bool isCached(Track track) => cached.contains(track.id);

  @override
  Future<File?> cacheTrackInBackground(Track track, String streamUrl) async {
    cachedUrls.add(streamUrl);
    cached.add(track.id);
    return File('/tmp/fake_${track.id}.mp3');
  }
}

void main() {
  group('TrackPreloadManager Unit Tests', () {
    late ProviderRegistry registry;
    late MockMusicProvider mockProvider;
    late FakeAudioCacheService cacheService;
    late SettingsService settingsService;
    late TrackPreloadManager preloadManager;

    setUp(() {
      registry = ProviderRegistry();
      mockProvider = MockMusicProvider('mock', 'Mock Provider');
      registry.registerProvider(mockProvider);

      cacheService = FakeAudioCacheService();
      settingsService = SettingsService();

      preloadManager = TrackPreloadManager(
        registry: registry,
        cacheService: cacheService,
        settingsService: settingsService,
        throttleDuration: Duration.zero,
      );
    });

    tearDown(() {
      preloadManager.dispose();
    });

    List<Track> createTrackList(int count) {
      return List.generate(count, (i) {
        return Track(
          id: 'track_$i',
          providerId: 'mock',
          title: 'Title $i',
          artist: 'Artist $i',
          duration: const Duration(seconds: 180),
          sourceUrl: 'http://mock/source_$i',
        );
      });
    }

    test('preloads next 10 tracks in sequence after start delay', () async {
      final queue = createTrackList(15);

      // Start playing index 0 -> should preload index 1 to 10 (10 tracks)
      preloadManager.schedulePreload(
        queue: queue,
        currentIndex: 0,
        startDelay: const Duration(milliseconds: 50),
      );

      // Before delay expires: nothing cached yet
      expect(cacheService.cachedUrls, isEmpty);

      // Wait for delay + preloading execution
      await Future.delayed(const Duration(milliseconds: 100));

      // Wait until preloads finish
      while (preloadManager.isPreloading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Should have cached up to 10 tracks (indices 1..10)
      expect(cacheService.cached.length, equals(10));
      expect(cacheService.cached.contains('track_0'), isFalse);
      expect(cacheService.cached.contains('track_1'), isTrue);
      expect(cacheService.cached.contains('track_10'), isTrue);
      expect(cacheService.cached.contains('track_11'), isFalse);
    });

    test('skips already cached tracks in the preload window', () async {
      final queue = createTrackList(5);
      // Mark track_1 and track_2 as already cached
      cacheService.cached.add('track_1');
      cacheService.cached.add('track_2');

      preloadManager.schedulePreload(
        queue: queue,
        currentIndex: 0,
        startDelay: const Duration(milliseconds: 20),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      while (preloadManager.isPreloading) {
        await Future.delayed(const Duration(milliseconds: 30));
      }

      // streamUrl should not have been called for track_1 and track_2
      expect(mockProvider.streamCallCounts['track_1'], isNull);
      expect(mockProvider.streamCallCounts['track_2'], isNull);
      expect(mockProvider.streamCallCounts['track_3'], equals(1));
      expect(mockProvider.streamCallCounts['track_4'], equals(1));
    });

    test('cancels active preloading when cancel() or new preload is scheduled', () async {
      final queue = createTrackList(20);

      // Schedule preload for index 0
      preloadManager.schedulePreload(
        queue: queue,
        currentIndex: 0,
        startDelay: const Duration(milliseconds: 100),
      );

      // Immediately user switches to index 5
      preloadManager.schedulePreload(
        queue: queue,
        currentIndex: 5,
        startDelay: const Duration(milliseconds: 20),
      );

      await Future.delayed(const Duration(milliseconds: 60));
      while (preloadManager.isPreloading) {
        await Future.delayed(const Duration(milliseconds: 30));
      }

      // Track 1-4 should not be preloaded because index 5 was chosen
      expect(cacheService.cached.contains('track_1'), isFalse);
      expect(cacheService.cached.contains('track_2'), isFalse);
      expect(cacheService.cached.contains('track_6'), isTrue);
    });

    test('wraps around queue when isRepeatAll is true', () async {
      final queue = createTrackList(4);

      // Queue of 4 items, current index is 2
      // Next 10 with repeat all should wrap: 3, 0, 1 (total 3 unique upcoming tracks)
      preloadManager.schedulePreload(
        queue: queue,
        currentIndex: 2,
        isRepeatAll: true,
        startDelay: const Duration(milliseconds: 20),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      while (preloadManager.isPreloading) {
        await Future.delayed(const Duration(milliseconds: 30));
      }

      expect(cacheService.cached.contains('track_3'), isTrue);
      expect(cacheService.cached.contains('track_0'), isTrue);
      expect(cacheService.cached.contains('track_1'), isTrue);
      expect(cacheService.cached.contains('track_2'), isFalse); // current track itself not preloaded
    });
  });
}
