import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core_player/data/local/database_helper.dart';
import 'package:core_player/data/services/sync_service.dart';
import 'package:core_player/domain/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncService Unit Tests', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      dbHelper = await DatabaseHelper.inMemory();
      final db = await dbHelper.database;
      await db.delete('settings');
      await db.delete('library');
      await db.delete('tracks');
    });

    test('initializes with default server URL and logged out state', () async {
      final sync = SyncService(dbHelper: dbHelper);
      await sync.init();

      expect(sync.serverUrl, equals('http://galik-tech.su'));
      expect(sync.isLoggedIn, isFalse);
      expect(sync.isSyncing, isFalse);
      expect(sync.token, isNull);
      expect(sync.username, isNull);
      expect(sync.lastSyncedAt, isNull);
    });

    test('updateServerUrl cleans URL and persists setting', () async {
      final sync = SyncService(dbHelper: dbHelper);
      await sync.init();

      sync.updateServerUrl('https://example.com/api/');
      expect(sync.serverUrl, equals('https://example.com/api'));

      final saved = await dbHelper.getSetting('sync_server_url');
      expect(saved, equals('https://example.com/api'));

      sync.updateServerUrl('myserver.local');
      expect(sync.serverUrl, equals('http://myserver.local'));
    });

    test('register successfully authenticates and stores credentials', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/register') {
          final body = json.decode(request.body);
          return http.Response(
            json.encode({
              'token': 'mock_jwt_token_123',
              'username': body['username'],
              'message': 'User registered successfully',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/sync/push') {
          return http.Response(
            json.encode({
              'status': 'synced',
              'library': [],
              'playlists': [],
              'history': [],
              'server_timestamp': 1000,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final sync = SyncService(dbHelper: dbHelper, client: mockClient);
      await sync.init();

      final ok = await sync.register('alex', 'secret123');
      expect(ok, isTrue);
      expect(sync.isLoggedIn, isTrue);
      expect(sync.token, equals('mock_jwt_token_123'));
      expect(sync.username, equals('alex'));

      final savedToken = await dbHelper.getSetting('sync_token');
      expect(savedToken, equals('mock_jwt_token_123'));
    });

    test('register failure sets status message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'detail': 'Username already taken'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final sync = SyncService(dbHelper: dbHelper, client: mockClient);
      await sync.init();

      final ok = await sync.register('existing_user', 'pass');
      expect(ok, isFalse);
      expect(sync.isLoggedIn, isFalse);
      expect(sync.statusMessage, contains('Username already taken'));
    });

    test('login successfully authenticates', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            json.encode({
              'token': 'login_token_456',
              'username': 'bob',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/sync/push') {
          return http.Response(
            json.encode({
              'status': 'synced',
              'library': [],
              'playlists': [],
              'history': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final sync = SyncService(dbHelper: dbHelper, client: mockClient);
      await sync.init();

      final ok = await sync.login('bob', 'password');
      expect(ok, isTrue);
      expect(sync.isLoggedIn, isTrue);
      expect(sync.token, equals('login_token_456'));
      expect(sync.username, equals('bob'));
    });

    test('login failure reports error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({'detail': 'Invalid credentials'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final sync = SyncService(dbHelper: dbHelper, client: mockClient);
      await sync.init();

      final ok = await sync.login('bob', 'wrongpass');
      expect(ok, isFalse);
      expect(sync.isLoggedIn, isFalse);
      expect(sync.statusMessage, contains('Invalid credentials'));
    });

    test('logout clears credentials and settings', () async {
      await dbHelper.setSetting('sync_token', 'token_to_clear');
      await dbHelper.setSetting('sync_username', 'user_to_clear');
      await dbHelper.setSetting('sync_last_synced_at', '2026-10-05T00:00:00Z');

      final sync = SyncService(dbHelper: dbHelper);
      await sync.init();
      expect(sync.isLoggedIn, isTrue);

      await sync.logout();
      expect(sync.isLoggedIn, isFalse);
      expect(sync.token, isNull);
      expect(sync.username, isNull);
      expect(sync.lastSyncedAt, isNull);

      final tokenSetting = await dbHelper.getSetting('sync_token');
      expect(tokenSetting, equals(''));
    });

    test('syncNow merges server tracks into local database', () async {
      final remoteTrack = Track(
        id: 'remote_track_1',
        title: 'Remote Song',
        artist: 'Cloud Artist',
        album: 'Cloud Album',
        duration: const Duration(seconds: 210),
        sourceUrl: 'https://example.com/remote.mp3',
        providerId: 'hitmo',
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/sync/push') {
          expect(request.headers['authorization'], equals('Bearer valid_token'));
          return http.Response(
            json.encode({
              'status': 'synced',
              'library': [remoteTrack.toMap()],
              'playlists': [],
              'history': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      await dbHelper.setSetting('sync_token', 'valid_token');
      await dbHelper.setSetting('sync_username', 'test_user');

      final sync = SyncService(dbHelper: dbHelper, client: mockClient);
      await sync.init();
      expect(sync.isLoggedIn, isTrue);

      // Verify local library is empty initially
      final initialTracks = await dbHelper.getLibraryTracks();
      expect(initialTracks.isEmpty, isTrue);

      final ok = await sync.syncNow();
      expect(ok, isTrue);
      expect(sync.statusMessage, contains('1'));

      // Verify remote track was merged into local library
      final updatedTracks = await dbHelper.getLibraryTracks();
      expect(updatedTracks.length, equals(1));
      expect(updatedTracks.first.id, equals('remote_track_1'));
      expect(updatedTracks.first.title, equals('Remote Song'));
      expect(updatedTracks.first.artist, equals('Cloud Artist'));
      expect(sync.lastSyncedAt, isNotNull);
    });
  });
}
