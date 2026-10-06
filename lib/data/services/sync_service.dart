import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../domain/models/track.dart';
import '../local/database_helper.dart';
import 'web_proxy_helper.dart';

class SyncService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final http.Client _client;

  String _serverUrl = WebProxyHelper.webOrigin;
  String? _token;
  String? _username;
  bool _isSyncing = false;
  DateTime? _lastSyncedAt;
  String? _statusMessage;

  SyncService({
    DatabaseHelper? dbHelper,
    http.Client? client,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _client = client ?? http.Client();

  String get serverUrl => _serverUrl;
  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get statusMessage => _statusMessage;

  Future<void> init() async {
    try {
      final savedUrl = await _dbHelper.getSetting('sync_server_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _serverUrl = savedUrl;
      }
      _token = await _dbHelper.getSetting('sync_token');
      _username = await _dbHelper.getSetting('sync_username');
      final lastSyncStr = await _dbHelper.getSetting('sync_last_synced_at');
      if (lastSyncStr != null && lastSyncStr.isNotEmpty) {
        _lastSyncedAt = DateTime.tryParse(lastSyncStr);
      }
      notifyListeners();

      if (isLoggedIn) {
        syncNow();
      }
    } catch (e) {
      if (kDebugMode) {
        print('SyncService init error: $e');
      }
    }
  }

  void updateServerUrl(String url) {
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'http://$cleanUrl';
    }
    _serverUrl = cleanUrl;
    _dbHelper.setSetting('sync_server_url', _serverUrl);
    notifyListeners();
  }

  Future<bool> register(String user, String pass, {String? customUrl}) async {
    if (customUrl != null && customUrl.isNotEmpty) updateServerUrl(customUrl);
    _isSyncing = true;
    _statusMessage = 'Регистрация...';
    notifyListeners();

    try {
      final uri = Uri.parse('$_serverUrl/api/auth/register');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': user.trim(), 'password': pass}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _username = data['username'];
        await _dbHelper.setSetting('sync_token', _token!);
        await _dbHelper.setSetting('sync_username', _username!);
        _statusMessage = 'Успешная регистрация!';
        _isSyncing = false;
        notifyListeners();
        await syncNow();
        return true;
      } else {
        try {
          final err = json.decode(response.body);
          _statusMessage = err['detail']?.toString() ?? 'Ошибка (${response.statusCode})';
        } catch (_) {
          _statusMessage = 'Ошибка (${response.statusCode}): ${response.body}';
        }
      }
    } catch (e) {
      _statusMessage = 'Ошибка подключения к серверу: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> login(String user, String pass, {String? customUrl}) async {
    if (customUrl != null && customUrl.isNotEmpty) updateServerUrl(customUrl);
    _isSyncing = true;
    _statusMessage = 'Вход...';
    notifyListeners();

    try {
      final uri = Uri.parse('$_serverUrl/api/auth/login');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': user.trim(), 'password': pass}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _username = data['username'];
        await _dbHelper.setSetting('sync_token', _token!);
        await _dbHelper.setSetting('sync_username', _username!);
        _statusMessage = 'Вход выполнен успешно!';
        _isSyncing = false;
        notifyListeners();
        await syncNow();
        return true;
      } else {
        try {
          final err = json.decode(response.body);
          _statusMessage = err['detail']?.toString() ?? 'Неверный логин или пароль';
        } catch (_) {
          _statusMessage = 'Ошибка (${response.statusCode})';
        }
      }
    } catch (e) {
      _statusMessage = 'Ошибка подключения: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    _lastSyncedAt = null;
    _statusMessage = null;
    await _dbHelper.setSetting('sync_token', '');
    await _dbHelper.setSetting('sync_username', '');
    await _dbHelper.setSetting('sync_last_synced_at', '');
    notifyListeners();
  }

  Future<bool> syncNow() async {
    if (!isLoggedIn) return false;
    _isSyncing = true;
    _statusMessage = 'Синхронизация...';
    notifyListeners();

    try {
      // 1. Get local tracks
      final localTracks = await _dbHelper.getLibraryTracks();
      final tracksPayload = localTracks.map((t) => t.toMap()).toList();

      // 2. Push to server and get merged results
      final uri = Uri.parse('$_serverUrl/api/sync/push');
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'library': tracksPayload,
          'playlists': [],
          'history': [],
          'settings': {},
          'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverLibrary = data['library'] as List? ?? [];

        // 3. Merge server tracks into local database
        final localTrackIds = localTracks.map((t) => t.id).toSet();
        int addedCount = 0;
        for (final item in serverLibrary) {
          if (item is Map<String, dynamic>) {
            final track = Track.fromMap(item);
            if (!localTrackIds.contains(track.id)) {
              await _dbHelper.addToLibrary(track);
              addedCount++;
            }
          }
        }

        _lastSyncedAt = DateTime.now();
        await _dbHelper.setSetting('sync_last_synced_at', _lastSyncedAt!.toIso8601String());
        _statusMessage = addedCount > 0
            ? 'Синхронизировано (+$addedCount новых треков)'
            : 'Медиатека актуальна';
        notifyListeners();
        return true;
      } else {
        _statusMessage = 'Ошибка сервера (${response.statusCode})';
      }
    } catch (e) {
      _statusMessage = 'Ошибка синхронизации: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }
}
