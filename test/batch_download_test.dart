import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';

class MockBatchProvider implements MusicProvider {
  @override
  String get providerId => 'mock';

  @override
  String get name => 'Mock';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async => [];

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async {
    return 'https://example.com/audio/${track.id}.mp3';
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Batch Download Tests', () {
    late ProviderRegistry registry;
    late LocalLibraryService libraryService;
    late DownloadManager manager;
    late http.Client mockClient;
    late Directory tempDownloadDir;

    setUp(() async {
      tempDownloadDir = await Directory.systemTemp.createTemp('batch_dl_test_');
      registry = ProviderRegistry();
      registry.registerProvider(MockBatchProvider());
      final dbHelper = await DatabaseHelper.inMemory();
      libraryService = LocalLibraryService(dbHelper: dbHelper);

      mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode('dummy mp3 binary content'),
          200,
          headers: {'content-type': 'audio/mpeg', 'content-length': '24'},
        );
      });

      manager = DownloadManager(
        registry: registry,
        libraryService: libraryService,
        dbHelper: dbHelper,
        client: mockClient,
        customDownloadDir: tempDownloadDir.path,
      );
    });

    tearDown(() async {
      if (await tempDownloadDir.exists()) {
        await tempDownloadDir.delete(recursive: true);
      }
    });

    test('downloadTracks downloads multiple downloadable tracks and filters non-downloadable', () async {
      final tracks = [
        Track(
          id: 'track_1',
          providerId: 'mock',
          title: 'Track 1',
          artist: 'Artist 1',
          duration: const Duration(minutes: 2),
          isStreamable: true,
          isDownloadable: true,
          sourceUrl: 'https://example.com/1',
        ),
        Track(
          id: 'track_2',
          providerId: 'mock',
          title: 'Track 2',
          artist: 'Artist 2',
          duration: const Duration(minutes: 3),
          isStreamable: true,
          isDownloadable: false, // NOT downloadable
          sourceUrl: '',
        ),
        Track(
          id: 'track_3',
          providerId: 'mock',
          title: 'Track 3',
          artist: 'Artist 3',
          duration: const Duration(minutes: 4),
          isStreamable: true,
          isDownloadable: true,
          sourceUrl: 'https://example.com/3',
        ),
      ];

      final scheduled = await manager.downloadTracks(tracks);
      expect(scheduled, equals(2));

      // Check task statuses
      expect(manager.tasks.length, equals(2));
      final task1 = manager.getTask('mock_track_1');
      final task3 = manager.getTask('mock_track_3');

      expect(task1, isNotNull);
      expect(task3, isNotNull);
      expect(task1!.status, equals(DownloadStatus.completed));
      expect(task3!.status, equals(DownloadStatus.completed));

      expect(manager.isDownloaded(tracks[0]), isTrue);
      expect(manager.isDownloaded(tracks[1]), isFalse);
      expect(manager.isDownloaded(tracks[2]), isTrue);
    });

    test('downloadTopN only downloads up to N downloadable tracks', () async {
      final tracks = List.generate(
        10,
        (i) => Track(
          id: 'top_$i',
          providerId: 'mock',
          title: 'Top Track $i',
          artist: 'Top Artist',
          duration: const Duration(minutes: 3),
          isStreamable: true,
          isDownloadable: true,
          sourceUrl: 'https://example.com/top_$i',
        ),
      );

      final scheduled = await manager.downloadTopN(tracks, 5);
      expect(scheduled, equals(5));
      expect(manager.tasks.length, equals(5));
      expect(manager.completedDownloadsCount, equals(5));
      expect(manager.activeDownloadsCount, equals(0));
    });

    test('downloadAll skips already completed tracks', () async {
      final track = Track(
        id: 'repeat_1',
        providerId: 'mock',
        title: 'Repeat Song',
        artist: 'Repeat Artist',
        duration: const Duration(minutes: 2),
        isStreamable: true,
        isDownloadable: true,
        sourceUrl: 'https://example.com/repeat',
      );

      // First download
      final firstCount = await manager.downloadAll([track]);
      expect(firstCount, equals(1));
      expect(manager.isDownloaded(track), isTrue);

      // Second download should skip
      final secondCount = await manager.downloadAll([track]);
      expect(secondCount, equals(0));
    });
  });
}
