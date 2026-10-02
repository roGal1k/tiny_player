import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_player/domain/models/equalizer_preset.dart';
import 'package:core_player/data/services/equalizer_service.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/presentation/screens/equalizer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EqualizerPreset model tests', () {
    test('contains 10 standard ISO bands and built-in presets', () {
      expect(EqualizerPreset.frequencyLabels.length, equals(10));
      expect(EqualizerPreset.frequencyHz.length, equals(10));
      expect(EqualizerPreset.frequencyLabels.first, equals('31 Hz'));
      expect(EqualizerPreset.frequencyLabels.last, equals('16 kHz'));

      expect(EqualizerPreset.defaultPresets.length, greaterThanOrEqualTo(10));
      final flat = EqualizerPreset.defaultPresets.firstWhere((p) => p.name == 'Flat');
      expect(flat.gains, everyElement(equals(0.0)));

      final rock = EqualizerPreset.defaultPresets.firstWhere((p) => p.name == 'Rock');
      expect(rock.gains[0], equals(4.5));
    });

    test('toMap and fromMap serialization works', () {
      const preset = EqualizerPreset(
        name: 'Test Preset',
        gains: [1.0, 2.0, 3.0, 4.0, 5.0, -1.0, -2.0, -3.0, -4.0, -5.0],
        preampDb: 1.5,
        isCustom: true,
      );

      final map = preset.toMap();
      final restored = EqualizerPreset.fromMap(map);

      expect(restored.name, equals('Test Preset'));
      expect(restored.gains, equals(preset.gains));
      expect(restored.preampDb, equals(1.5));
      expect(restored.isCustom, isTrue);
    });
  });

  group('EqualizerService unit tests', () {
    late DatabaseHelper dbHelper;

    setUpAll(() async {
      dbHelper = await DatabaseHelper.inMemory();
    });

    test('initializes with default flat values and handles toggle', () async {
      final service = EqualizerService(dbHelper: dbHelper);
      expect(service.isEnabled, isFalse);
      expect(service.bandGains.length, equals(10));
      expect(service.bandGains, everyElement(equals(0.0)));
      expect(service.preampDb, equals(0.0));
      expect(service.playbackRate, equals(1.0));
      expect(service.balance, equals(0.0));

      service.toggleEnabled();
      expect(service.isEnabled, isTrue);

      service.toggleEnabled(false);
      expect(service.isEnabled, isFalse);
    });

    test('setBandGain clamps between -12 and +12 and sets preset to Custom', () {
      final service = EqualizerService(dbHelper: dbHelper);
      service.setBandGain(0, 5.5);
      expect(service.bandGains[0], equals(5.5));
      expect(service.currentPresetName, equals('Custom'));

      // Test clamping
      service.setBandGain(1, 20.0);
      expect(service.bandGains[1], equals(12.0));

      service.setBandGain(2, -25.0);
      expect(service.bandGains[2], equals(-12.0));
    });

    test('applyPreset and resetToFlat update bands and preamp', () {
      final service = EqualizerService(dbHelper: dbHelper);
      final rock = EqualizerPreset.defaultPresets.firstWhere((p) => p.name == 'Rock');

      service.applyPreset(rock);
      expect(service.currentPresetName, equals('Rock'));
      expect(service.bandGains[0], equals(4.5));
      expect(service.preampDb, equals(1.0));

      service.resetToFlat();
      expect(service.currentPresetName, equals('Flat'));
      expect(service.bandGains, everyElement(equals(0.0)));
      expect(service.preampDb, equals(0.0));
    });

    test('playback rate and balance trigger callbacks', () {
      final service = EqualizerService(dbHelper: dbHelper);
      double? receivedRate;
      double? receivedBalance;

      service.onPlaybackRateChanged = (r) => receivedRate = r;
      service.onBalanceChanged = (b) => receivedBalance = b;

      service.setPlaybackRate(1.25);
      expect(service.playbackRate, equals(1.25));
      expect(receivedRate, equals(1.25));

      service.setBalance(-0.5);
      expect(service.balance, equals(-0.5));
      expect(receivedBalance, equals(-0.5));
    });

    test('custom preset saving and persistence across instances', () async {
      final service = EqualizerService(dbHelper: dbHelper);
      service.setBandGain(0, 7.0);
      service.setPreamp(2.0);
      service.setPlaybackRate(1.1);
      service.toggleEnabled(true);
      service.saveCustomPreset('My SubBass');

      expect(service.currentPresetName, equals('My SubBass'));
      expect(service.customPresets.any((p) => p.name == 'My SubBass'), isTrue);

      // Re-init with new service instance reading from same DB
      final service2 = EqualizerService(dbHelper: dbHelper);
      await service2.init();

      expect(service2.isEnabled, isTrue);
      expect(service2.bandGains[0], equals(7.0));
      expect(service2.preampDb, equals(2.0));
      expect(service2.playbackRate, equals(1.1));
      expect(service2.currentPresetName, equals('My SubBass'));
      expect(service2.customPresets.any((p) => p.name == 'My SubBass'), isTrue);
    });
  });

  group('EqualizerScreen widget tests', () {
    testWidgets('renders tabs, controls, faders and interacts with state', (tester) async {
      final equalizerService = EqualizerService(persistToDb: false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<EqualizerService>.value(
            value: equalizerService,
            child: const EqualizerScreen(),
          ),
        ),
      );

      // Verify header and master switch
      expect(find.text('ЭКВАЛАЙЗЕР & ТЮНЕР'), findsOneWidget);
      expect(find.text('ВЫКЛ'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      // Toggle switch to ON
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('ВКЛ'), findsOneWidget);
      expect(equalizerService.isEnabled, isTrue);

      // Verify 10-band labels
      expect(find.text('Preamp'), findsOneWidget);
      expect(find.text('31Hz'), findsOneWidget);
      expect(find.text('1kHz'), findsOneWidget);
      expect(find.text('16kHz'), findsOneWidget);

      // Switch to "ТЮНЕР И ЭФФЕКТЫ" tab
      await tester.tap(find.text('ТЮНЕР И ЭФФЕКТЫ'));
      await tester.pumpAndSettle();

      // Verify tuner UI
      expect(find.text('ТЮНЕР & ТЕМП ВОСПРОИЗВЕДЕНИЯ'), findsOneWidget);
      expect(find.text('СТЕРЕО-БАЛАНС КАНАЛОВ'), findsOneWidget);
      expect(find.text('УСИЛЕНИЕ БАСОВ (BASS BOOST)'), findsOneWidget);
      expect(find.text('1.25x'), findsOneWidget);

      // Tap on 1.25x chip
      await tester.tap(find.text('1.25x'));
      await tester.pumpAndSettle();
      expect(equalizerService.playbackRate, equals(1.25));
    });
  });
}
