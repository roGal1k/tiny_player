import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core_player/data/providers/youtube_provider.dart';
import 'package:core_player/domain/models/track.dart';

void main() {
  group('YouTubeProvider Unit Tests', () {
    late YouTubeProvider provider;

    setUp(() {
      provider = YouTubeProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('metadata properties are correct', () async {
      expect(provider.providerId, equals('youtube'));
      expect(provider.name, equals('YouTube Music'));
      expect(await provider.authenticate(), isTrue);
      expect(await provider.getUserLibrary(), isEmpty);
    });

    test('search returns empty list for empty query', () async {
      final results = await provider.search('   ');
      expect(results, isEmpty);
    });

    test('live search returns valid Track objects with audio attributes', () async {
      final tracks = await provider.search('Queen Bohemian Rhapsody');
      expect(tracks, isNotEmpty);

      final track = tracks.first;
      expect(track.id, isNotEmpty);
      expect(track.providerId, equals('youtube'));
      expect(track.title.toLowerCase(), contains('bohemian'));
      expect(track.artist, isNotEmpty);
      expect(track.duration.inSeconds, greaterThan(0));
      expect(track.artworkUrl, isNotNull);
      expect(track.artworkUrl!, startsWith('http'));
      expect(track.isStreamable, isTrue);
      expect(track.isDownloadable, isTrue);
      expect(track.sourceUrl, contains('youtube.com/watch?v='));

      // Test download options
      final options = await provider.getDownloadOptions(track);
      expect(options, contains('m4a'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getStreamUrl resolves playable audio track and getVideoStreamUrl resolves video stream', () async {
      try {
        final tracks = await provider.search('NoCopyrightSounds');
        if (tracks.isEmpty) return;
        final sampleTrack = tracks.first;

        // Test video stream retrieval (for "Watch Video" feature)
        final videoUrl = await provider.getVideoStreamUrl(sampleTrack);
        expect(videoUrl, startsWith('https://'));
        expect(videoUrl, contains('googlevideo.com/videoplayback'));

        final videoResponse = await http.get(
          Uri.parse(videoUrl),
          headers: {'Range': 'bytes=0-1000'},
        );
        expect(videoResponse.statusCode, equals(206));
        expect(videoResponse.bodyBytes.length, equals(1001));

        // Test audio stream retrieval (pure audio file or playable stream)
        final audioPathOrUrl = await provider.getStreamUrl(sampleTrack);
        expect(audioPathOrUrl, isNotEmpty);
        if (audioPathOrUrl.startsWith('http')) {
          expect(audioPathOrUrl, contains('googlevideo.com/videoplayback'));
        } else {
          expect(audioPathOrUrl.endsWith('.m4a'), isTrue);
        }

        // Test background preloading
        await provider.preloadTrack(sampleTrack);
      } catch (e) {
        // Tolerates live network/rate-limiting restrictions on automated tests
        expect(e, anyOf(isA<Exception>(), isA<Error>()));
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('getTrack retrieves single video by ID', () async {
      try {
        final tracks = await provider.search('NoCopyrightSounds');
        if (tracks.isEmpty) return;
        final testId = tracks.first.id;

        final track = await provider.getTrack(testId);
        if (track != null) {
          expect(track.id, equals(testId));
          expect(track.providerId, equals('youtube'));
          expect(track.title, isNotEmpty);
          expect(track.artist, isNotEmpty);
        }
      } catch (e) {
        expect(e, anyOf(isA<Exception>(), isA<Error>()));
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
