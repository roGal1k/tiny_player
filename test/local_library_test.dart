import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/providers/local_provider.dart';
import 'package:core_player/data/services/local_library_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('LocalProvider and DatabaseHelper insert, get and search tracks', () async {
    final dbHelper = await DatabaseHelper.inMemory();
    final localProvider = LocalProvider(dbHelper: dbHelper);

    final track = Track(
      id: 'test_local_1',
      providerId: 'local',
      title: 'Aerodynamic',
      artist: 'Daft Punk',
      album: 'Discovery',
      duration: const Duration(minutes: 3, seconds: 27),
      isStreamable: true,
      isDownloadable: false,
      sourceUrl: '/fake/path/Aerodynamic.mp3',
    );

    await dbHelper.addToLibrary(track);

    final libraryTracks = await localProvider.getUserLibrary();
    expect(libraryTracks.any((t) => t.id == 'test_local_1'), isTrue);

    final searchResults = await localProvider.search('Daft');
    expect(searchResults.any((t) => t.title == 'Aerodynamic'), isTrue);

    final streamUrl = await localProvider.getStreamUrl(track);
    expect(streamUrl, equals('/fake/path/Aerodynamic.mp3'));

    await dbHelper.removeFromLibrary('test_local_1');
  });

  test('LocalLibraryService scans directory and detects audio files', () async {
    final tempDir = await Directory.systemTemp.createTemp('core_player_test_');
    final dummyMp3 = File('${tempDir.path}/Queen - Bohemian Rhapsody.mp3');
    await dummyMp3.writeAsString('dummy mp3 content');

    final dbHelper = await DatabaseHelper.inMemory();
    final libraryService = LocalLibraryService(dbHelper: dbHelper);
    final added = await libraryService.scanDirectory(tempDir.path);

    expect(added, equals(1));
    expect(libraryService.tracks.any((t) => t.title == 'Bohemian Rhapsody'), isTrue);
    expect(libraryService.tracks.any((t) => t.artist == 'Queen'), isTrue);

    // Cleanup
    await tempDir.delete(recursive: true);
  });

  test('LocalLibraryService handles favorites toggle and query', () async {
    final dbHelper = await DatabaseHelper.inMemory();
    final libraryService = LocalLibraryService(dbHelper: dbHelper);
    await libraryService.loadLibrary();

    const track = Track(
      id: 'fav_track_1',
      providerId: 'hitmo',
      title: 'Midnight City',
      artist: 'M83',
      duration: Duration(minutes: 4, seconds: 3),
      sourceUrl: 'https://example.com/stream.mp3',
    );

    expect(libraryService.isFavorite('fav_track_1'), isFalse);

    // Add to favorites
    final added = await libraryService.toggleFavorite(track);
    expect(added, isTrue);
    expect(libraryService.isFavorite('fav_track_1'), isTrue);

    // Remove from favorites
    final removed = await libraryService.toggleFavorite(track);
    expect(removed, isFalse);
    expect(libraryService.isFavorite('fav_track_1'), isFalse);
  });
}
