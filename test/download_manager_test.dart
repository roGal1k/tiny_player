import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DownloadTask tracks progress, status and file path', () {
    final track = Track(
      id: 'sc_12345',
      providerId: 'soundcloud',
      title: 'Test Song',
      artist: 'Test Artist',
      duration: const Duration(minutes: 3),
      isStreamable: true,
      isDownloadable: true,
      sourceUrl: 'https://example.com/audio.mp3',
    );

    final task = DownloadTask(track: track);
    expect(task.status, equals(DownloadStatus.downloading));
    expect(task.progress, equals(0.0));

    task.downloadedBytes = 500;
    task.totalBytes = 1000;
    task.progress = 0.5;
    expect(task.progress, equals(0.5));

    task.status = DownloadStatus.completed;
    task.savedFilePath = '/path/to/song.mp3';
    expect(task.status, equals(DownloadStatus.completed));
    expect(task.savedFilePath, equals('/path/to/song.mp3'));
  });

  test('DownloadManager registers and queries download tasks', () async {
    final registry = ProviderRegistry();
    final libraryService = LocalLibraryService();
    final manager = DownloadManager(
      registry: registry,
      libraryService: libraryService,
    );

    final track = Track(
      id: 'jamendo_99',
      providerId: 'jamendo',
      title: 'Summer Breeze',
      artist: 'Solaris',
      duration: const Duration(minutes: 2, seconds: 40),
      isStreamable: true,
      isDownloadable: true,
      sourceUrl: '',
    );

    expect(manager.tasks.isEmpty, isTrue);
    expect(manager.getTask('jamendo_99'), isNull);
  });
}
