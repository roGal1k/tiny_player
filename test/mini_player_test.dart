import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/presentation/widgets/mini_player_widget.dart';

void main() {
  testWidgets('MiniPlayerWidget renders and reacts to controller state', (WidgetTester tester) async {
    final registry = ProviderRegistry();
    final controller = AudioPlayerController(registry: registry);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AudioPlayerController>.value(
            value: controller,
            child: const MiniPlayerWidget(),
          ),
        ),
      ),
    );

    // Initially track is null, so MiniPlayer is SizedBox.shrink()
    expect(find.byType(MiniPlayerWidget), findsOneWidget);
    expect(find.text('Test Track'), findsNothing);

    // Now simulate setting a track
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AudioPlayerController>.value(
            value: controller,
            child: const MiniPlayerWidget(),
          ),
        ),
      ),
    );

    // Clean up
    controller.dispose();
  });
}
