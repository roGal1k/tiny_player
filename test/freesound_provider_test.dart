import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/data/providers/freesound_provider.dart';

void main() {
  test('FreesoundProvider has correct metadata and handles empty key', () async {
    final providerWithoutKey = FreesoundProvider();
    expect(providerWithoutKey.providerId, equals('freesound'));
    expect(providerWithoutKey.name, equals('Freesound'));
    expect(await providerWithoutKey.authenticate(), isFalse);
    expect(await providerWithoutKey.search('test'), isEmpty);

    final providerWithKey = FreesoundProvider(apiKey: 'dummy_key');
    expect(await providerWithKey.authenticate(), isTrue);
  });
}
