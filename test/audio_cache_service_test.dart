import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/services/audio_cache_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AudioCacheService Tests', () {
    late Directory tempCacheDir;
    late DatabaseHelper dbHelper;

    setUp(() async {
      tempCacheDir = await Directory.systemTemp.createTemp('audio_cache_test_');
      dbHelper = await DatabaseHelper.inMemory();
    });

    tearDown(() async {
      try {
        if (await tempCacheDir.exists()) {
          await tempCacheDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('formatBytes formats file sizes correctly', () {
      final service = AudioCacheService(
        dbHelper: dbHelper,
        customCacheDir: tempCacheDir.path,
      );

      expect(service.formatBytes(500), equals('500 B'));
      expect(service.formatBytes(1536), equals('1.5 KB'));
      expect(service.formatBytes(5 * 1024 * 1024), equals('5.0 MB'));
      expect(service.formatBytes(2 * 1024 * 1024 * 1024), equals('2.00 GB'));
    });

    test('caches track stream in background and plays offline', () async {
      // Create a mock HTTP client that returns > 4KB of audio data
      final mockData = List.filled(5000, 42);
      final client = MockClient((request) async {
        return http.Response.bytes(mockData, 200);
      });

      final service = AudioCacheService(
        dbHelper: dbHelper,
        client: client,
        customCacheDir: tempCacheDir.path,
      );

      await service.init();
      expect(service.cachedCount, equals(0));

      final track = Track(
        id: 'hitmo_12345',
        providerId: 'hitmo',
        title: 'Super Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: const Duration(minutes: 3, seconds: 15),
        isStreamable: true,
        isDownloadable: true,
        sourceUrl: 'https://example.com/audio/12345.mp3',
      );

      expect(service.isCached(track), isFalse);

      // Cache track in background
      final cachedFile = await service.cacheTrackInBackground(track, 'https://example.com/audio/12345.mp3');

      expect(cachedFile, isNotNull);
      expect(await cachedFile!.exists(), isTrue);
      expect(await cachedFile.length(), equals(5000));
      expect(service.isCached(track), isTrue);
      expect(service.cachedCount, equals(1));

      // Check database persistence
      final cachedTracks = await service.getCachedTracks();
      expect(cachedTracks.length, equals(1));
      expect(cachedTracks.first.id, equals('hitmo_12345'));
      expect(cachedTracks.first.title, equals('Super Test Song'));

      // Remove from cache
      await service.removeTrackFromCache(track);
      expect(service.isCached(track), isFalse);
      expect(service.cachedCount, equals(0));
      expect(await cachedFile.exists(), isFalse);

      final cachedAfterDelete = await service.getCachedTracks();
      expect(cachedAfterDelete.isEmpty, isTrue);
    });

    test('syncs pre-existing files on disk during init', () async {
      // Pre-populate a valid audio file in cache dir
      final preFile = File('${tempCacheDir.path}/hitmo_disk999.mp3');
      await preFile.writeAsBytes(List.filled(6000, 1));

      final service = AudioCacheService(
        dbHelper: dbHelper,
        customCacheDir: tempCacheDir.path,
      );

      await service.init();

      final diskTrack = Track(
        id: 'disk999',
        providerId: 'hitmo',
        title: 'Disk Track',
        artist: 'Disk Artist',
        duration: const Duration(minutes: 2),
        isStreamable: true,
        isDownloadable: false,
        sourceUrl: '',
      );

      expect(service.isCached(diskTrack), isTrue);
      final retrieved = service.getCachedFile(diskTrack);
      expect(retrieved, isNotNull);
      expect(retrieved!.path, equals(preFile.path));

      // Clear cache clears everything
      await service.clearCache();
      expect(service.isCached(diskTrack), isFalse);
      expect(service.cachedCount, equals(0));
      expect(await preFile.exists(), isFalse);
    });
  });
}
