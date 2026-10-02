import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../domain/models/equalizer_preset.dart';
import '../local/database_helper.dart';

class EqualizerService extends ChangeNotifier {
  final DatabaseHelper? _dbHelper;

  bool _isEnabled = false;
  double _preampDb = 0.0;
  List<double> _bandGains = List.filled(10, 0.0);
  String _currentPresetName = 'Flat';
  double _playbackRate = 1.0;
  double _balance = 0.0;
  double _bassBoost = 0.0; // 0.0 to 1.0
  List<EqualizerPreset> _customPresets = [];

  // Listeners / hooks for audio engine
  ValueChanged<double>? onPlaybackRateChanged;
  ValueChanged<double>? onBalanceChanged;
  ValueChanged<double>? onVolumeMultiplierChanged;

  EqualizerService({DatabaseHelper? dbHelper, bool persistToDb = true})
      : _dbHelper = persistToDb ? (dbHelper ?? DatabaseHelper.instance) : null;

  bool get isEnabled => _isEnabled;
  double get preampDb => _preampDb;
  List<double> get bandGains => List.unmodifiable(_bandGains);
  String get currentPresetName => _currentPresetName;
  double get playbackRate => _playbackRate;
  double get balance => _balance;
  double get bassBoost => _bassBoost;
  List<EqualizerPreset> get customPresets => List.unmodifiable(_customPresets);

  List<EqualizerPreset> get allPresets => [
        ...EqualizerPreset.defaultPresets,
        ..._customPresets,
      ];

  Future<void> init() async {
    if (_dbHelper == null) return;
    try {
      final jsonStr = await _dbHelper!.getSetting('equalizer_settings');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        _isEnabled = data['isEnabled'] as bool? ?? false;
        _preampDb = (data['preampDb'] as num?)?.toDouble() ?? 0.0;
        _currentPresetName = data['currentPresetName'] as String? ?? 'Flat';
        _playbackRate = (data['playbackRate'] as num?)?.toDouble() ?? 1.0;
        _balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
        _bassBoost = (data['bassBoost'] as num?)?.toDouble() ?? 0.0;

        final rawGains = data['bandGains'] as List<dynamic>?;
        if (rawGains != null && rawGains.length == 10) {
          _bandGains = rawGains.map((e) => (e as num).toDouble()).toList();
        }

        final rawCustom = data['customPresets'] as List<dynamic>?;
        if (rawCustom != null) {
          _customPresets = rawCustom
              .map((e) => EqualizerPreset.fromMap(e as Map<String, dynamic>))
              .toList();
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persistSettings() async {
    if (_dbHelper == null) return;
    try {
      final data = {
        'isEnabled': _isEnabled,
        'preampDb': _preampDb,
        'bandGains': _bandGains,
        'currentPresetName': _currentPresetName,
        'playbackRate': _playbackRate,
        'balance': _balance,
        'bassBoost': _bassBoost,
        'customPresets': _customPresets.map((p) => p.toMap()).toList(),
      };
      await _dbHelper!.setSetting('equalizer_settings', json.encode(data));
    } catch (_) {}
  }

  void toggleEnabled([bool? value]) {
    _isEnabled = value ?? !_isEnabled;
    notifyListeners();
    _applyVolumeMultiplier();
    _persistSettings();
  }

  void setBandGain(int bandIndex, double gainDb) {
    if (bandIndex < 0 || bandIndex >= _bandGains.length) return;
    _bandGains[bandIndex] = gainDb.clamp(-12.0, 12.0);
    _currentPresetName = 'Custom';
    notifyListeners();
    _persistSettings();
  }

  void setPreamp(double gainDb) {
    _preampDb = gainDb.clamp(-12.0, 12.0);
    notifyListeners();
    _applyVolumeMultiplier();
    _persistSettings();
  }

  void applyPreset(EqualizerPreset preset) {
    _currentPresetName = preset.name;
    _bandGains = List<double>.from(preset.gains);
    _preampDb = preset.preampDb;
    notifyListeners();
    _applyVolumeMultiplier();
    _persistSettings();
  }

  void resetToFlat() {
    applyPreset(EqualizerPreset.defaultPresets.first); // Flat
  }

  void setPlaybackRate(double rate) {
    _playbackRate = rate.clamp(0.5, 2.0);
    onPlaybackRateChanged?.call(_playbackRate);
    notifyListeners();
    _persistSettings();
  }

  void setBalance(double bal) {
    _balance = bal.clamp(-1.0, 1.0);
    onBalanceChanged?.call(_balance);
    notifyListeners();
    _persistSettings();
  }

  void setBassBoost(double value) {
    _bassBoost = value.clamp(0.0, 1.0);
    // When bass boost is turned up, dynamically influence 31Hz and 63Hz if enabled
    if (_isEnabled && _bassBoost > 0) {
      _bandGains[0] = (_bandGains[0] + _bassBoost * 2.0).clamp(-12.0, 12.0);
      _bandGains[1] = (_bandGains[1] + _bassBoost * 1.5).clamp(-12.0, 12.0);
    }
    notifyListeners();
    _persistSettings();
  }

  void saveCustomPreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final newPreset = EqualizerPreset(
      name: trimmed,
      gains: List<double>.from(_bandGains),
      preampDb: _preampDb,
      isCustom: true,
    );

    _customPresets.removeWhere((p) => p.name.toLowerCase() == trimmed.toLowerCase());
    _customPresets.add(newPreset);
    _currentPresetName = trimmed;
    notifyListeners();
    _persistSettings();
  }

  void deleteCustomPreset(String name) {
    _customPresets.removeWhere((p) => p.name == name);
    if (_currentPresetName == name) {
      resetToFlat();
    } else {
      notifyListeners();
      _persistSettings();
    }
  }

  void _applyVolumeMultiplier() {
    if (!_isEnabled) {
      onVolumeMultiplierChanged?.call(1.0);
      return;
    }
    // Calculate linear gain multiplier from preamp dB
    // dB = 20 * log10(multiplier) => multiplier = 10 ^ (dB / 20)
    final linearMultiplier = _preampDb == 0.0 ? 1.0 : (1.0 + (_preampDb / 12.0) * 0.5).clamp(0.1, 1.5);
    onVolumeMultiplierChanged?.call(linearMultiplier);
  }
}
