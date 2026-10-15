import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../domain/models/artist.dart';
import '../../domain/models/track.dart';
import '../local/database_helper.dart';
import 'artist_service.dart';
import 'web_proxy_helper.dart';

class VpsFileInfo {
  final String filename;
  final bool exists;
  final int sizeBytes;
  final int? mtimeMs;
  final int? updatedAt;
  final int tracksCount;
  final int artistsCount;
  final int cachedCount;

  const VpsFileInfo({
    required this.filename,
    required this.exists,
    required this.sizeBytes,
    this.mtimeMs,
    this.updatedAt,
    required this.tracksCount,
    required this.artistsCount,
    this.cachedCount = 0,
  });

  factory VpsFileInfo.fromMap(Map<String, dynamic> map) {
    return VpsFileInfo(
      filename: map['filename'] as String? ?? 'user_data.json',
      exists: map['exists'] as bool? ?? false,
      sizeBytes: map['size_bytes'] as int? ?? 0,
      mtimeMs: map['mtime_ms'] as int?,
      updatedAt: map['updated_at'] as int?,
      tracksCount: map['tracks_count'] as int? ?? 0,
      artistsCount: map['artists_count'] as int? ?? 0,
      cachedCount: map['cached_count'] as int? ?? 0,
    );
  }
}

class SyncService extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final http.Client _client;
  ArtistService? _artistService;

  String _serverUrl = WebProxyHelper.webOrigin;
  String? _token;
  String? _username;
  bool _isSyncing = false;
  DateTime? _lastSyncedAt;
  String? _statusMessage;
  VpsFileInfo? _vpsFileInfo;
  Timer? _autoSyncTimer;

  SyncService({
    DatabaseHelper? dbHelper,
    http.Client? client,
    ArtistService? artistService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _client = client ?? http.Client(),
        _artistService = artistService;

  void setArtistService(ArtistService service) {
    _artistService = service;
  }

  String get serverUrl => _serverUrl;
  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get statusMessage => _statusMessage;
  VpsFileInfo? get vpsFileInfo => _vpsFileInfo;

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

      if (!isLoggedIn) {
        // Auto-login to unified ecosystem profile
        await login('admin', 'bwatMP1234');
      } else {
        await syncNow();
        await fetchVpsFileInfo();
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
    _autoSyncTimer?.cancel();
    _token = null;
    _username = null;
    _lastSyncedAt = null;
    _vpsFileInfo = null;
    _statusMessage = null;
    await _dbHelper.setSetting('sync_token', '');
    await _dbHelper.setSetting('sync_username', '');
    await _dbHelper.setSetting('sync_last_synced_at', '');
    notifyListeners();
  }

  void scheduleAutoSync() {
    if (!isLoggedIn) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 3), () {
      syncNow();
    });
  }

  Future<bool> syncNow() async {
    if (!isLoggedIn) return false;
    _isSyncing = true;
    _statusMessage = 'Синхронизация...';
    notifyListeners();

    try {
      // 1. Get local tracks, favorite artists, and cached tracks
      final localTracks = await _dbHelper.getLibraryTracks();
      final tracksPayload = localTracks.map((t) => t.toMap()).toList();

      final localArtists = await _dbHelper.getFavoriteArtists();
      final artistsPayload = localArtists.map((a) => a.toMap()).toList();

      final localCachedTracks = await _dbHelper.getCachedTracks();
      final cachedPayload = localCachedTracks.map((t) => t.toMap()).toList();

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
          'artists': artistsPayload,
          'cached_tracks': cachedPayload,
          'playlists': [],
          'history': [],
          'settings': {},
          'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverLibrary = data['library'] as List? ?? [];
        final serverArtists = data['artists'] as List? ?? [];
        final serverCached = data['cached_tracks'] as List? ?? [];

        // 3. Merge server tracks into local database
        final localTrackIds = localTracks.map((t) => t.id).toSet();
        int addedTracksCount = 0;
        for (final item in serverLibrary) {
          if (item is Map<String, dynamic>) {
            final track = Track.fromMap(item);
            if (!localTrackIds.contains(track.id)) {
              await _dbHelper.addToLibrary(track);
              addedTracksCount++;
            }
          }
        }

        // 4. Merge server artists into local database
        final localArtistNames = localArtists.map((a) => a.name.trim().toLowerCase()).toSet();
        int addedArtistsCount = 0;
        for (final item in serverArtists) {
          if (item is Map<String, dynamic>) {
            final artist = Artist.fromMap(item);
            if (!localArtistNames.contains(artist.name.trim().toLowerCase())) {
              await _dbHelper.addFavoriteArtist(artist);
              addedArtistsCount++;
            }
          }
        }

        if (addedArtistsCount > 0 && _artistService != null) {
          await _artistService!.loadFavorites();
        }

        _lastSyncedAt = DateTime.now();
        await _dbHelper.setSetting('sync_last_synced_at', _lastSyncedAt!.toIso8601String());

        final summaryParts = <String>[];
        if (addedTracksCount > 0) summaryParts.add('+$addedTracksCount треков');
        if (addedArtistsCount > 0) summaryParts.add('+$addedArtistsCount авторов');

        _statusMessage = summaryParts.isNotEmpty
            ? 'Синхронизировано (${summaryParts.join(', ')})'
            : 'Данные актуальны (сохранены в файл на VPS)';

        await fetchVpsFileInfo();
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

  Future<VpsFileInfo?> fetchVpsFileInfo() async {
    if (!isLoggedIn) return null;
    try {
      final uri = Uri.parse('$_serverUrl/api/user/file/info');
      final resp = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        _vpsFileInfo = VpsFileInfo.fromMap(data);
        notifyListeners();
        return _vpsFileInfo;
      }
    } catch (e) {
      if (kDebugMode) {
        print('fetchVpsFileInfo error: $e');
      }
    }
    return null;
  }

  Future<bool> saveBackupFileToVps() async {
    return await syncNow();
  }

  Future<bool> restoreFromVpsFile() async {
    if (!isLoggedIn) return false;
    _isSyncing = true;
    _statusMessage = 'Восстановление из файла на VPS...';
    notifyListeners();

    try {
      final uri = Uri.parse('$_serverUrl/api/user/file/download');
      final resp = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        if (data is Map<String, dynamic>) {
          final count = await _dbHelper.importFullUserData(data);
          if (_artistService != null) {
            await _artistService!.loadFavorites();
          }
          _lastSyncedAt = DateTime.now();
          await _dbHelper.setSetting('sync_last_synced_at', _lastSyncedAt!.toIso8601String());
          await fetchVpsFileInfo();
          _statusMessage = 'Восстановлено из файла на VPS ($count объектов)';
          notifyListeners();
          return true;
        }
      } else {
        _statusMessage = 'Ошибка загрузки файла с VPS (${resp.statusCode})';
      }
    } catch (e) {
      _statusMessage = 'Ошибка восстановления: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }

  Future<String> exportLocalBackupJson() async {
    final data = await _dbHelper.exportFullUserData();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<int> importLocalBackupJson(String jsonString) async {
    try {
      final data = json.decode(jsonString);
      if (data is Map<String, dynamic>) {
        final count = await _dbHelper.importFullUserData(data);
        if (_artistService != null) {
          await _artistService!.loadFavorites();
        }
        if (isLoggedIn) {
          scheduleAutoSync();
        }
        notifyListeners();
        return count;
      }
    } catch (e) {
      if (kDebugMode) {
        print('importLocalBackupJson error: $e');
      }
    }
    return 0;
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
