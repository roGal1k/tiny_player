import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/data/providers/hitmo_provider.dart';

void main() {
  test('HitmoProvider metadata and HTML parser extracts tracks correctly', () {
    final provider = HitmoProvider(mirrorUrl: 'https://ru.hitmoz.org');
    expect(provider.providerId, equals('hitmo'));
    expect(provider.name, equals('Hitmo'));

    const sampleHtml = '''
    <!DOCTYPE html>
    <html>
      <body>
        <ul class="tracks__list">
          <li class="tracks__item" data-musmeta='{"img":"https://statcore.hitmcdn.com/cover/123.jpg"}'>
            <div class="track__info">
              <div class="track__title">Numb</div>
              <div class="track__desc">Linkin Park</div>
              <div class="track__fulltime">03:07</div>
              <a class="track__download-btn" href="/get/998877.mp3"></a>
            </div>
          </li>
          <li class="tracks__item">
            <div class="track__info">
              <div class="track__title">Faint</div>
              <div class="track__desc">Linkin Park</div>
              <div class="track__fulltime">02:42</div>
              <a class="track__download-btn" href="https://dl.hitmoz.org/get/112233.mp3"></a>
            </div>
          </li>
        </ul>
      </body>
    </html>
    ''';

    final tracks = provider.parseHtmlTracks(sampleHtml);
    expect(tracks.length, equals(2));

    expect(tracks[0].title, equals('Numb'));
    expect(tracks[0].artist, equals('Linkin Park'));
    expect(tracks[0].duration, equals(const Duration(minutes: 3, seconds: 7)));
    expect(tracks[0].sourceUrl, equals('https://ru.hitmoz.org/get/998877.mp3'));
    expect(tracks[0].artworkUrl, equals('https://statcore.hitmcdn.com/cover/123.jpg'));
    expect(tracks[0].isStreamable, isTrue);
    expect(tracks[0].isDownloadable, isTrue);

    expect(tracks[1].title, equals('Faint'));
    expect(tracks[1].duration, equals(const Duration(minutes: 2, seconds: 42)));
    expect(tracks[1].sourceUrl, equals('https://dl.hitmoz.org/get/112233.mp3'));
    expect(tracks[1].artworkUrl, isNull);
  });

  test('HitmoProvider live search returns tracks without geo-block', () async {
    final provider = HitmoProvider();
    final results = await provider.search('Queen');
    // Live verification
    expect(results, isNotEmpty);
    expect(results.first.title.isNotEmpty, isTrue);
    expect(results.first.artist.isNotEmpty, isTrue);

    final streamUrl = await provider.getStreamUrl(results.first);
    expect(streamUrl.isNotEmpty, isTrue);

    final popular = await provider.getPopularTracks();
    expect(popular, isNotEmpty);

    final topHits = await provider.search('Top Hits 2024');
    print('Top Hits 2024 results count: ${topHits.length}');
    expect(topHits, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 15)));
}
