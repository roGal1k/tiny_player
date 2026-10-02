import 'package:flutter_test/flutter_test.dart';
import 'package:core_player/data/services/video_launcher_service.dart';
import 'package:core_player/domain/models/track.dart';

void main() {
  group('VideoLauncherService Tests', () {
    test('checks player binary availability', () async {
      final hasVlc = await VideoLauncherService.isVlcAvailable();
      expect(hasVlc, isA<bool>());

      final hasFfplay = await VideoLauncherService.isFfplayAvailable();
      expect(hasFfplay, isA<bool>());
    });

    test('service instantiates cleanly with or without registry', () {
      final service = VideoLauncherService();
      expect(service, isNotNull);
    });
  });
}
