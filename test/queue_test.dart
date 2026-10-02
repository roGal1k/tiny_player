import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/data/services/download_manager.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:core_player/presentation/screens/queue_screen.dart';
import 'package:core_player/presentation/widgets/mini_player_widget.dart';
import 'fake_audioplayers.dart';

AudioPlayerController createTestController({required ProviderRegistry registry}) {
  final player = FakeAudioPlayer();
  return AudioPlayerController(registry: registry, player: player);
}

class MockQueueMusicProvider implements MusicProvider {
  @override
  String get providerId => 'mock_q';

  @override
  String get name => 'MockQueue';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async => [];

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => track.sourceUrl;

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

Track makeTestTrack(String id, {String title = 'Test Title', bool isDownloadable = true}) {
  return Track(
    id: id,
    providerId: 'mock_q',
    title: title,
    artist: 'Test Artist',
    duration: const Duration(seconds: 180),
    isStreamable: true,
    isDownloadable: isDownloadable,
    sourceUrl: 'https://example.com/$id.mp3',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioplayersPlatformInterface.instance = FakeAudioplayersPlatform();
  GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioplayersPlatform();

  late ProviderRegistry registry;
  late MockQueueMusicProvider mockProvider;

  setUp(() {
    registry = ProviderRegistry();
    mockProvider = MockQueueMusicProvider();
    registry.registerProvider(mockProvider);
  });

  group('AudioPlayerController Queue & Playlist unit tests', () {
    test('initial queue is empty and repeatMode is all by default', () {
      final controller = createTestController(registry: registry);
      expect(controller.queue, isEmpty);
      expect(controller.currentIndex, equals(-1));
      expect(controller.repeatMode, equals(PlaybackRepeatMode.all));
      expect(controller.isShuffle, isFalse);
      expect(controller.hasNext, isFalse);
      expect(controller.hasPrevious, isFalse);
    });

    test('playTrack with playlist initializes queue and sets currentIndex', () async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track 1'),
        makeTestTrack('2', title: 'Track 2'),
        makeTestTrack('3', title: 'Track 3'),
      ];

      await controller.playTrack(tracks[1], playlist: tracks);

      expect(controller.queue.length, equals(3));
      expect(controller.currentIndex, equals(1));
      expect(controller.currentTrack?.id, equals('2'));
      expect(controller.hasNext, isTrue);
      expect(controller.hasPrevious, isTrue);
    });

    test('playNext advances queue and loops with PlaybackRepeatMode.all', () async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track 1'),
        makeTestTrack('2', title: 'Track 2'),
      ];

      await controller.playTrack(tracks[0], playlist: tracks);
      expect(controller.currentIndex, equals(0));

      // Play next -> track 2
      await controller.playNext();
      expect(controller.currentIndex, equals(1));
      expect(controller.currentTrack?.id, equals('2'));

      // End of queue with PlaybackRepeatMode.all -> loops to track 1
      await controller.playNext();
      expect(controller.currentIndex, equals(0));
      expect(controller.currentTrack?.id, equals('1'));

      // With PlaybackRepeatMode.off -> stops at end of queue
      controller.setRepeatMode(PlaybackRepeatMode.off);
      await controller.playNext(); // goes to 1
      expect(controller.currentIndex, equals(1));
      await controller.playNext(); // stops
      expect(controller.currentTrack, isNull);
    });

    test('playPrevious returns to previous track or seeks to start', () async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track 1'),
        makeTestTrack('2', title: 'Track 2'),
      ];

      await controller.playTrack(tracks[1], playlist: tracks);
      expect(controller.currentIndex, equals(1));

      await controller.playPrevious();
      expect(controller.currentIndex, equals(0));
      expect(controller.currentTrack?.id, equals('1'));
    });

    test('removeFromQueue removes item and auto-advances if current is removed', () async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track 1'),
        makeTestTrack('2', title: 'Track 2'),
        makeTestTrack('3', title: 'Track 3'),
      ];

      await controller.playTrack(tracks[1], playlist: tracks);
      expect(controller.currentIndex, equals(1));

      // Remove current track (Track 2)
      await controller.removeFromQueue(1);
      expect(controller.queue.length, equals(2));
      // Current index now points to Track 3
      expect(controller.currentTrack?.id, equals('3'));

      // Remove preceding track (Track 1)
      await controller.removeFromQueue(0);
      expect(controller.queue.length, equals(1));
      expect(controller.currentIndex, equals(0));
      expect(controller.currentTrack?.id, equals('3'));

      // Remove the last track
      await controller.removeFromQueue(0);
      expect(controller.queue, isEmpty);
      expect(controller.currentIndex, equals(-1));
      expect(controller.currentTrack, isNull);
    });

    test('reorderQueue rearranges tracks and preserves currentTrack index', () async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track 1'),
        makeTestTrack('2', title: 'Track 2'),
        makeTestTrack('3', title: 'Track 3'),
      ];

      await controller.playTrack(tracks[1], playlist: tracks);
      expect(controller.currentIndex, equals(1)); // Track 2

      // Move Track 1 (index 0) to end (index 3 in reorder logic)
      controller.reorderQueue(0, 3);
      // New order: [Track 2, Track 3, Track 1]
      expect(controller.queue[0].id, equals('2'));
      expect(controller.queue[1].id, equals('3'));
      expect(controller.queue[2].id, equals('1'));
      // Current index should now be 0 (still pointing to Track 2)
      expect(controller.currentIndex, equals(0));
    });

    test('repeatMode and shuffle toggles cycle properly', () {
      final controller = createTestController(registry: registry);

      expect(controller.repeatMode, equals(PlaybackRepeatMode.all));
      controller.toggleRepeatMode();
      expect(controller.repeatMode, equals(PlaybackRepeatMode.one));
      controller.toggleRepeatMode();
      expect(controller.repeatMode, equals(PlaybackRepeatMode.off));
      controller.toggleRepeatMode();
      expect(controller.repeatMode, equals(PlaybackRepeatMode.all));

      expect(controller.isShuffle, isFalse);
      controller.toggleShuffle();
      expect(controller.isShuffle, isTrue);
      controller.toggleShuffle();
      expect(controller.isShuffle, isFalse);
    });

    test('clearQueue empties queue and stops audio', () async {
      final controller = createTestController(registry: registry);
      final tracks = [makeTestTrack('1'), makeTestTrack('2')];

      await controller.playTrack(tracks[0], playlist: tracks);
      expect(controller.queue.length, equals(2));

      await controller.clearQueue();
      expect(controller.queue, isEmpty);
      expect(controller.currentIndex, equals(-1));
      expect(controller.currentTrack, isNull);
    });
  });

  group('QueueScreen Widget Tests', () {
    testWidgets('renders empty state when queue is empty', (tester) async {
      final controller = createTestController(registry: registry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AudioPlayerController>.value(
              value: controller,
              child: const QueueScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ТРЕКЛИСТ & ОЧЕРЕДЬ'), findsOneWidget);
      expect(find.text('Очередь пуста'), findsOneWidget);
      expect(find.text('Очередь воспроизведения пуста'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('renders queue tracks, highlights active track and handles interactions', (tester) async {
      final controller = createTestController(registry: registry);
      final tracks = [
        makeTestTrack('1', title: 'Track Alpha'),
        makeTestTrack('2', title: 'Track Beta'),
        makeTestTrack('3', title: 'Track Gamma'),
      ];

      await controller.playTrack(tracks[0], playlist: tracks);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AudioPlayerController>.value(
              value: controller,
              child: const QueueScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ТРЕКЛИСТ & ОЧЕРЕДЬ'), findsOneWidget);
      expect(find.text('Трек 1 из 3'), findsOneWidget);
      expect(find.text('Track Alpha'), findsOneWidget);
      expect(find.text('Track Beta'), findsOneWidget);
      expect(find.text('Track Gamma'), findsOneWidget);

      // Tap on Track Beta to play
      await tester.tap(find.text('Track Beta'));
      await tester.pumpAndSettle();
      expect(controller.currentIndex, equals(1));
      expect(controller.currentTrack?.title, equals('Track Beta'));
      expect(find.text('Трек 2 из 3'), findsOneWidget);

      // Tap remove button on first track (Track Alpha)
      final closeButtons = find.byIcon(Icons.close);
      expect(closeButtons, findsNWidgets(3));
      await tester.tap(closeButtons.first);
      await tester.pumpAndSettle();

      expect(controller.queue.length, equals(2));
      expect(find.text('Track Alpha'), findsNothing);
      expect(find.text('Track Beta'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('MiniPlayerWidget contains queue button and opens modal', (tester) async {
      final controller = createTestController(registry: registry);
      final track = makeTestTrack('1', title: 'Playing Track');
      await controller.playTrack(track, playlist: [track]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AudioPlayerController>.value(value: controller),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: MiniPlayerWidget(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Check for queue button
      final queueButton = find.byIcon(Icons.queue_music);
      expect(queueButton, findsOneWidget);

      // Tap queue button -> opens bottom sheet
      await tester.tap(queueButton);
      await tester.pumpAndSettle();

      expect(find.text('ТРЕКЛИСТ & ОЧЕРЕДЬ'), findsOneWidget);
      expect(find.text('Playing Track'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}
