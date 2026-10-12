import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core_player/data/providers/hitmo_provider.dart';

void main() {
  test('Hitmo mirrors check', () async {
    final mirrors = [
      'https://ru.hitmoz.org',
      'https://rur.hitmotop.com',
      'https://hitmo.org',
      'https://hitmotop.com',
    ];

    final headers = {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      'X-Forwarded-For': '85.249.20.1',
      'X-Real-IP': '85.249.20.1',
      'CF-Connecting-IP': '85.249.20.1',
    };

    for (final m in mirrors) {
      final sw = Stopwatch()..start();
      try {
        final res = await http.get(Uri.parse('$m/search?q=queen'), headers: headers).timeout(const Duration(seconds: 5));
        sw.stop();
        print('Mirror $m => Status: ${res.statusCode}, Length: ${res.body.length}, Time: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        sw.stop();
        print('Mirror $m => Error: $e in ${sw.elapsedMilliseconds}ms');
      }
    }
  });

  test('HitmoProvider getStreamUrl resolves 302 redirect to direct CDN stream', () async {
    final provider = HitmoProvider();
    final tracks = await provider.search('queen');
    expect(tracks.isNotEmpty, isTrue);

    final firstTrack = tracks.first;
    expect(firstTrack.sourceUrl, isNotEmpty);

    final streamUrl = await provider.getStreamUrl(firstTrack);
    print('Resolved stream URL: $streamUrl');
    expect(streamUrl.startsWith('http'), isTrue);
    // Should resolve redirect to CDN or valid audio stream
    expect(streamUrl.contains('/get/music/') || streamUrl.contains('deliciousoranges') || streamUrl.contains('cdn'), isTrue);

    // Repeat call should hit instant memory cache
    final sw = Stopwatch()..start();
    final cachedUrl = await provider.getStreamUrl(firstTrack);
    sw.stop();
    expect(cachedUrl, equals(streamUrl));
    expect(sw.elapsedMilliseconds, lessThan(10));
  });
}
