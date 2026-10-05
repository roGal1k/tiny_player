import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../local/database_helper.dart';

class SettingsService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final http.Client _client;

  double _volume = 1.0;
  bool _isMuted = false;
  String _themeMode = 'dark'; // 'dark', 'oled', 'light', 'system'
  String _accentColor = 'cyan'; // 'cyan', 'purple', 'emerald', 'amber', 'pink'
  String _hitmoMirrorUrl = 'https://ru.hitmoz.org';
  final Set<String> _disabledProviders = {};
  bool _autoPlayNext = true;
  bool _autoCacheAudio = true;
  double _defaultPlaybackRate = 1.0;
  String _downloadPath = '';

  SettingsService({
    DatabaseHelper? dbHelper,
    http.Client? client,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _client = client ?? http.Client();

  // Getters
  double get volume => _volume;
  bool get isMuted => _isMuted;
  String get themeMode => _themeMode;
  String get accentColor => _accentColor;
  String get hitmoMirrorUrl => _hitmoMirrorUrl;
  Set<String> get disabledProviders => Set.unmodifiable(_disabledProviders);
  bool get autoPlayNext => _autoPlayNext;
  bool get autoCacheAudio => _autoCacheAudio;
  double get defaultPlaybackRate => _defaultPlaybackRate;
  String get downloadPath => _downloadPath;

  bool isProviderEnabled(String providerId) => !_disabledProviders.contains(providerId.toLowerCase());

  Color get accentColorValue {
    switch (_accentColor.toLowerCase()) {
      case 'purple':
        return Colors.purpleAccent;
      case 'emerald':
        return Colors.tealAccent;
      case 'amber':
        return Colors.amberAccent;
      case 'pink':
        return Colors.pinkAccent;
      case 'cyan':
      default:
        return Colors.cyanAccent;
    }
  }

  Color get primaryColorValue {
    switch (_accentColor.toLowerCase()) {
      case 'purple':
        return Colors.deepPurple;
      case 'emerald':
        return Colors.teal;
      case 'amber':
        return Colors.amber;
      case 'pink':
        return Colors.pink;
      case 'cyan':
      default:
        return Colors.cyan;
    }
  }

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'oled':
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  ThemeData get themeData {
    final isOled = _themeMode == 'oled';
    final isLight = _themeMode == 'light';

    if (isLight) {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        primaryColor: primaryColorValue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColorValue,
          brightness: Brightness.light,
          primary: primaryColorValue,
          secondary: accentColorValue,
        ),
        dividerColor: Colors.black12,
      );
    }

    final scaffoldBg = isOled ? Colors.black : const Color(0xFF0F1117);
    final cardBg = isOled ? const Color(0xFF161922) : const Color(0xFF1B1E28);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: primaryColorValue,
      cardColor: cardBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColorValue,
        brightness: Brightness.dark,
        surface: scaffoldBg,
        primary: primaryColorValue,
        secondary: accentColorValue,
      ),
      dividerColor: Colors.white12,
    );
  }

  Future<void> loadSettings() async {
    try {
      final volStr = await _dbHelper.getSetting('settings_volume');
      if (volStr != null) {
        _volume = double.tryParse(volStr)?.clamp(0.0, 1.0) ?? 1.0;
      }

      final mutedStr = await _dbHelper.getSetting('settings_is_muted');
      if (mutedStr != null) {
        _isMuted = mutedStr == 'true';
      }

      final themeStr = await _dbHelper.getSetting('settings_theme_mode');
      if (themeStr != null && themeStr.isNotEmpty) {
        _themeMode = themeStr;
      }

      final accentStr = await _dbHelper.getSetting('settings_accent_color');
      if (accentStr != null && accentStr.isNotEmpty) {
        _accentColor = accentStr;
      }

      final mirrorStr = await _dbHelper.getSetting('settings_hitmo_mirror_url');
      if (mirrorStr != null && mirrorStr.trim().isNotEmpty) {
        _hitmoMirrorUrl = mirrorStr.trim();
      }

      final disabledStr = await _dbHelper.getSetting('settings_disabled_providers');
      if (disabledStr != null && disabledStr.isNotEmpty) {
        _disabledProviders.clear();
        try {
          final list = jsonDecode(disabledStr) as List<dynamic>;
          _disabledProviders.addAll(list.map((e) => e.toString().toLowerCase()));
        } catch (_) {
          final list = disabledStr.split(',').where((e) => e.trim().isNotEmpty);
          _disabledProviders.addAll(list.map((e) => e.trim().toLowerCase()));
        }
      }

      final autoNextStr = await _dbHelper.getSetting('settings_auto_play_next');
      if (autoNextStr != null) {
        _autoPlayNext = autoNextStr == 'true';
      }

      final autoCacheStr = await _dbHelper.getSetting('settings_auto_cache_audio');
      if (autoCacheStr != null) {
        _autoCacheAudio = autoCacheStr == 'true';
      }

      final rateStr = await _dbHelper.getSetting('settings_default_playback_rate');
      if (rateStr != null) {
        _defaultPlaybackRate = double.tryParse(rateStr)?.clamp(0.5, 2.0) ?? 1.0;
      }

      final pathStr = await _dbHelper.getSetting('settings_download_path');
      if (pathStr != null) {
        _downloadPath = pathStr;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    notifyListeners();
    await _dbHelper.setSetting('settings_volume', _volume.toString());
    await _dbHelper.setSetting('settings_is_muted', _isMuted.toString());
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    notifyListeners();
    await _dbHelper.setSetting('settings_is_muted', _isMuted.toString());
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    await _dbHelper.setSetting('settings_is_muted', _isMuted.toString());
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    notifyListeners();
    await _dbHelper.setSetting('settings_theme_mode', _themeMode);
  }

  Future<void> setAccentColor(String color) async {
    _accentColor = color;
    notifyListeners();
    await _dbHelper.setSetting('settings_accent_color', _accentColor);
  }

  Future<void> setHitmoMirrorUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isNotEmpty) {
      _hitmoMirrorUrl = clean;
      notifyListeners();
      await _dbHelper.setSetting('settings_hitmo_mirror_url', _hitmoMirrorUrl);
    }
  }

  Future<bool> testHitmoMirror(String url) async {
    try {
      final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(clean);
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          'X-Forwarded-For': '85.249.20.1',
          'X-Real-IP': '85.249.20.1',
          'CF-Connecting-IP': '85.249.20.1',
        },
      ).timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    final key = providerId.toLowerCase();
    if (enabled) {
      _disabledProviders.remove(key);
    } else {
      _disabledProviders.add(key);
    }
    notifyListeners();
    await _dbHelper.setSetting('settings_disabled_providers', jsonEncode(_disabledProviders.toList()));
  }

  Future<void> setAutoPlayNext(bool value) async {
    _autoPlayNext = value;
    notifyListeners();
    await _dbHelper.setSetting('settings_auto_play_next', _autoPlayNext.toString());
  }

  Future<void> setAutoCacheAudio(bool value) async {
    _autoCacheAudio = value;
    notifyListeners();
    await _dbHelper.setSetting('settings_auto_cache_audio', _autoCacheAudio.toString());
  }

  Future<void> setDefaultPlaybackRate(double rate) async {
    _defaultPlaybackRate = rate.clamp(0.5, 2.0);
    notifyListeners();
    await _dbHelper.setSetting('settings_default_playback_rate', _defaultPlaybackRate.toString());
  }

  Future<void> setDownloadPath(String path) async {
    _downloadPath = path.trim();
    notifyListeners();
    await _dbHelper.setSetting('settings_download_path', _downloadPath);
  }
}
