// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/main.dart';
import 'package:core_player/data/providers/provider_registry.dart';

import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/services/download_manager.dart';

void main() {
  testWidgets('CorePlayerApp smoke test', (WidgetTester tester) async {
    final registry = ProviderRegistry();
    final localLibraryService = LocalLibraryService();
    final downloadManager = DownloadManager(
      registry: registry,
      libraryService: localLibraryService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProviderRegistry>.value(value: registry),
          ChangeNotifierProvider<LocalLibraryService>.value(value: localLibraryService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<AudioPlayerController>(
            create: (_) => AudioPlayerController(registry: registry),
          ),
        ],
        child: const CorePlayerApp(),
      ),
    );

    expect(find.text('Home'), findsWidgets);
  });
}
