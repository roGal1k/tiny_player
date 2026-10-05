import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/services/settings_service.dart';
import 'package:core_player/data/services/equalizer_service.dart';
import 'package:core_player/data/services/local_library_service.dart';
import 'package:core_player/data/providers/provider_registry.dart';
import 'package:core_player/presentation/controllers/audio_player_controller.dart';
import 'package:core_player/presentation/screens/settings_screen.dart';
import 'package:core_player/presentation/widgets/mini_player_widget.dart';
import 'package:core_player/domain/models/track.dart';
import 'package:core_player/domain/providers/music_provider.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'fake_audioplayers.dart';

class MockMusicProvider implements MusicProvider {
  @override
  String get providerId => 'test_provider';

  @override
  String get name => 'Test Music';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async => [];

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async => 'https://example.com/audio.mp3';

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioplayersPlatformInterface.instance = FakeAudioplayersPlatform();
  GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioplayersPlatform();

  group('SettingsService Unit Tests', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
    });

    test('initializes with default values', () {
      final settings = SettingsService(dbHelper: dbHelper);
      expect(settings.volume, equals(1.0));
      expect(settings.isMuted, isFalse);
      expect(settings.themeMode, equals('dark'));
      expect(settings.accentColor, equals('cyan'));
      expect(settings.hitmoMirrorUrl, equals('https://ru.hitmoz.org'));
      expect(settings.disabledProviders, isEmpty);
      expect(settings.autoPlayNext, isTrue);
      expect(settings.defaultPlaybackRate, equals(1.0));
    });

    test('volume and mute persistence and listener notification', () async {
      final settings = SettingsService(dbHelper: dbHelper);
      int notified = 0;
      settings.addListener(() => notified++);

      await settings.setVolume(0.65);
      expect(settings.volume, equals(0.65));
      expect(notified, equals(1));

      final persistedVol = await dbHelper.getSetting('settings_volume');
      expect(persistedVol, equals('0.65'));

      await settings.toggleMute();
      expect(settings.isMuted, isTrue);
      expect(notified, equals(2));

      final persistedMute = await dbHelper.getSetting('settings_is_muted');
      expect(persistedMute, equals('true'));

      await settings.setMuted(false);
      expect(settings.isMuted, isFalse);
      expect(notified, equals(3));
    });

    test('theme mode and accent colors affect ThemeData and flutterThemeMode', () async {
      final settings = SettingsService(dbHelper: dbHelper);

      await settings.setThemeMode('light');
      expect(settings.flutterThemeMode, equals(ThemeMode.light));
      expect(settings.themeData.brightness, equals(Brightness.light));

      await settings.setThemeMode('oled');
      expect(settings.flutterThemeMode, equals(ThemeMode.dark));
      expect(settings.themeData.scaffoldBackgroundColor, equals(Colors.black));

      await settings.setAccentColor('emerald');
      expect(settings.accentColorValue, equals(Colors.tealAccent));
      expect(settings.primaryColorValue, equals(Colors.teal));

      await settings.setAccentColor('purple');
      expect(settings.accentColorValue, equals(Colors.purpleAccent));
      expect(settings.primaryColorValue, equals(Colors.deepPurple));
    });

    test('Hitmo mirror URL cleaning and persistence', () async {
      final settings = SettingsService(dbHelper: dbHelper);
      await settings.setHitmoMirrorUrl('https://custom.hitmo.me///');
      expect(settings.hitmoMirrorUrl, equals('https://custom.hitmo.me'));

      final persisted = await dbHelper.getSetting('settings_hitmo_mirror_url');
      expect(persisted, equals('https://custom.hitmo.me'));
    });

    test('enabling and disabling providers', () async {
      final settings = SettingsService(dbHelper: dbHelper);
      expect(settings.isProviderEnabled('hitmo'), isTrue);

      await settings.setProviderEnabled('hitmo', false);
      expect(settings.isProviderEnabled('hitmo'), isFalse);
      expect(settings.disabledProviders.contains('hitmo'), isTrue);

      await settings.setProviderEnabled('hitmo', true);
      expect(settings.isProviderEnabled('hitmo'), isTrue);
      expect(settings.disabledProviders.contains('hitmo'), isFalse);
    });

    test('loadSettings restores previously stored state from database', () async {
      await dbHelper.setSetting('settings_volume', '0.42');
      await dbHelper.setSetting('settings_is_muted', 'true');
      await dbHelper.setSetting('settings_theme_mode', 'light');
      await dbHelper.setSetting('settings_accent_color', 'pink');
      await dbHelper.setSetting('settings_hitmo_mirror_url', 'https://mirror.saved');
      await dbHelper.setSetting('settings_disabled_providers', '["vk", "jamendo"]');
      await dbHelper.setSetting('settings_auto_play_next', 'false');
      await dbHelper.setSetting('settings_default_playback_rate', '1.25');

      final settings = SettingsService(dbHelper: dbHelper);
      await settings.loadSettings();

      expect(settings.volume, closeTo(0.42, 0.001));
      expect(settings.isMuted, isTrue);
      expect(settings.themeMode, equals('light'));
      expect(settings.accentColor, equals('pink'));
      expect(settings.hitmoMirrorUrl, equals('https://mirror.saved'));
      expect(settings.disabledProviders, containsAll(['vk', 'jamendo']));
      expect(settings.isProviderEnabled('vk'), isFalse);
      expect(settings.isProviderEnabled('hitmo'), isTrue);
      expect(settings.autoPlayNext, isFalse);
      expect(settings.defaultPlaybackRate, equals(1.25));
    });
  });

  group('AudioPlayerController Volume & Settings Integration Tests', () {
    late DatabaseHelper dbHelper;
    late SettingsService settings;
    late ProviderRegistry registry;
    late FakeAudioPlayer player;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
      settings = SettingsService(dbHelper: dbHelper);
      await settings.setVolume(0.8);
      registry = ProviderRegistry();
      registry.registerProvider(MockMusicProvider());
      player = FakeAudioPlayer();
    });

    test('AudioPlayerController initializes volume and mute from settingsService', () {
      final controller = AudioPlayerController(
        registry: registry,
        settingsService: settings,
        player: player,
      );

      expect(controller.volume, equals(0.8));
      expect(controller.rawVolume, equals(0.8));
      expect(controller.isMuted, isFalse);
      controller.dispose();
    });

    test('AudioPlayerController setVolume updates controller and persists to settingsService', () async {
      final controller = AudioPlayerController(
        registry: registry,
        settingsService: settings,
        player: player,
      );

      await controller.setVolume(0.45);
      expect(controller.volume, equals(0.45));
      expect(settings.volume, equals(0.45));

      final persisted = await dbHelper.getSetting('settings_volume');
      expect(persisted, equals('0.45'));
      controller.dispose();
    });

    test('AudioPlayerController toggleMute sets volume to 0.0 and syncs state', () async {
      final controller = AudioPlayerController(
        registry: registry,
        settingsService: settings,
        player: player,
      );

      expect(controller.isMuted, isFalse);
      await controller.toggleMute();
      expect(controller.isMuted, isTrue);
      expect(controller.volume, equals(0.0));
      expect(controller.rawVolume, equals(0.8));
      expect(settings.isMuted, isTrue);

      // Unmute via setVolume
      await controller.setVolume(0.9);
      expect(controller.isMuted, isFalse);
      expect(controller.volume, equals(0.9));
      expect(settings.isMuted, isFalse);
      controller.dispose();
    });
  });

  group('SettingsScreen Widget Tests', () {
    late DatabaseHelper dbHelper;
    late SettingsService settings;
    late ProviderRegistry registry;
    late EqualizerService equalizer;
    late LocalLibraryService libraryService;
    late AudioPlayerController audioCtrl;
    late FakeAudioPlayer player;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
      settings = SettingsService(dbHelper: dbHelper);
      registry = ProviderRegistry();
      registry.registerProvider(MockMusicProvider());
      equalizer = EqualizerService(dbHelper: dbHelper);
      libraryService = LocalLibraryService(dbHelper: dbHelper);
      player = FakeAudioPlayer();
      audioCtrl = AudioPlayerController(
        registry: registry,
        settingsService: settings,
        equalizerService: equalizer,
        player: player,
      );
    });

    tearDown(() {
      audioCtrl.dispose();
      equalizer.dispose();
    });

    testWidgets('renders all 5 main sections and handles theme changes', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<AudioPlayerController>.value(value: audioCtrl),
            ChangeNotifierProvider<EqualizerService>.value(value: equalizer),
            ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
            Provider<ProviderRegistry>.value(value: registry),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      // Check section headers
      expect(find.text('Настройки'), findsOneWidget);
      expect(find.text('Аудио и Воспроизведение'), findsOneWidget);
      expect(find.text('Источники и Зеркала'), findsOneWidget);
      expect(find.text('Хранилище и Библиотека'), findsOneWidget);
      expect(find.text('Внешний вид и Оформление'), findsOneWidget);
      expect(find.text('О приложении'), findsOneWidget);

      // Check audio elements
      expect(find.text('Основная громкость'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Автовоспроизведение очереди'), findsOneWidget);

      // Check Hitmo mirror text field
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Проверить пинг'), findsOneWidget);
      expect(find.text('Сохранить'), findsOneWidget);

      // Check Theme chips
      expect(find.text('Темная'), findsOneWidget);
      expect(find.text('OLED Черная'), findsOneWidget);
      expect(find.text('Светлая'), findsOneWidget);
      expect(find.text('Системная'), findsOneWidget);

      // Tap OLED chip
      await tester.tap(find.text('OLED Черная'));
      await tester.pump(const Duration(seconds: 11));
      expect(settings.themeMode, equals('oled'));

      // Check version text
      expect(find.text('CorePlayer'), findsOneWidget);
      expect(find.text('Версия 1.2.0 • Pro Edition'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    });

    testWidgets('toggling provider switch updates SettingsService and ProviderRegistry', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<AudioPlayerController>.value(value: audioCtrl),
            ChangeNotifierProvider<EqualizerService>.value(value: equalizer),
            ChangeNotifierProvider<LocalLibraryService>.value(value: libraryService),
            Provider<ProviderRegistry>.value(value: registry),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Test Music'), findsOneWidget);
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsWidgets);

      // Toggle first provider switch
      final providerTile = find.widgetWithText(SwitchListTile, 'Test Music');
      await tester.tap(find.descendant(of: providerTile, matching: find.byType(Switch)));
      await tester.pump(const Duration(seconds: 11));

      expect(settings.isProviderEnabled('test_provider'), isFalse);
      expect(registry.isProviderEnabled('test_provider'), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    });
  });

  group('MiniPlayerWidget Volume Control Widget Tests', () {
    late DatabaseHelper dbHelper;
    late SettingsService settings;
    late ProviderRegistry registry;
    late FakeAudioPlayer player;
    late AudioPlayerController audioCtrl;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
      settings = SettingsService(dbHelper: dbHelper);
      registry = ProviderRegistry();
      registry.registerProvider(MockMusicProvider());
      player = FakeAudioPlayer();
      audioCtrl = AudioPlayerController(
        registry: registry,
        settingsService: settings,
        player: player,
      );
    });

    tearDown(() {
      audioCtrl.dispose();
    });

    testWidgets('MiniPlayerWidget displays volume button and opens popup dialog', (tester) async {
      const track = Track(
        id: 't1',
        providerId: 'test_provider',
        title: 'Song With Volume',
        artist: 'Test Artist',
        duration: Duration(seconds: 120),
        isStreamable: true,
        sourceUrl: 'https://example.com/audio.mp3',
      );

      await audioCtrl.playTrack(track, playlist: [track]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AudioPlayerController>.value(value: audioCtrl),
            ChangeNotifierProvider<SettingsService>.value(value: settings),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MiniPlayerWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // On standard test resolution (800x600 > 680), desktop inline volume is displayed
      final volumeIcon = find.byIcon(Icons.volume_up);
      expect(volumeIcon, findsWidgets);

      // Volume sliders are available
      final sliders = find.byType(Slider);
      expect(sliders, findsWidgets);
    });
  });
}
