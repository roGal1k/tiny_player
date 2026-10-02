import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/data/providers/hitmo_provider.dart';

void main() {
  test('Hitmo Cyrillic searches', () async {
    final hitmo = HitmoProvider();
    for (final q in ['кино', 'король и шут', 'баста', 'queen', 'miyagi']) {
      final sw = Stopwatch()..start();
      final tracks = await hitmo.search(q);
      sw.stop();
      print('Query "$q" => found ${tracks.length} tracks in ${sw.elapsedMilliseconds}ms');
      if (tracks.isNotEmpty) {
        print('  First: ${tracks.first.title} - ${tracks.first.artist}');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
