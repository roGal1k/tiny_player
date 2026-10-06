import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/web_proxy_helper.dart';
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class AudiusProvider implements MusicProvider {
  final http.Client _client;
  final String _baseUrl;

  AudiusProvider({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://discoveryprovider.audius.co/v1';

  @override
  String get providerId => 'audius';

  @override
  String get name => 'Audius';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/tracks/search').replace(queryParameters: {
      'query': cleanQuery,
      'app_name': 'CorePlayer',
    });

    try {
      final response = await _client.get(WebProxyHelper.proxyUri(uri));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final data = decoded['data'] as List?;
        if (data == null) return [];

        return data
            .map((item) => _mapToTrack(item as Map<String, dynamic>))
            .whereType<Track>()
            .toList();
      } else {
        if (kDebugMode) {
          print('Audius search error: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Audius search exception: $e');
      }
    }
    return [];
  }

  @override
  Future<Track?> getTrack(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;

    final uri = Uri.parse('$_baseUrl/tracks/$cleanId').replace(queryParameters: {
      'app_name': 'CorePlayer',
    });

    try {
      final response = await _client.get(WebProxyHelper.proxyUri(uri));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        var data = decoded['data'];
        if (data is List && data.isNotEmpty) {
          data = data.first;
        }
        if (data is Map<String, dynamic>) {
          return _mapToTrack(data);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Audius getTrack exception for $id: $e');
      }
    }
    return null;
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    if (track.sourceUrl.isNotEmpty) {
      return track.sourceUrl;
    }
    return '$_baseUrl/tracks/${track.id}/stream?app_name=CorePlayer';
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async => ['mp3'];

  @override
  Future<List<Track>> getUserLibrary() async => [];

  Track? _mapToTrack(Map<String, dynamic> item) {
    try {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) return null;

      final title = item['title']?.toString() ?? 'Unknown Track';
      final user = item['user'] as Map<String, dynamic>?;
      final artist = user?['name']?.toString() ?? user?['handle']?.toString() ?? 'Audius Artist';
      final artwork = item['artwork'] as Map<String, dynamic>?;
      final artworkUrl = artwork?['480x480']?.toString() ??
          artwork?['150x150']?.toString() ??
          artwork?['1000x1000']?.toString();

      final durationSec = item['duration'] is num
          ? (item['duration'] as num).toInt()
          : int.tryParse(item['duration']?.toString() ?? '0') ?? 0;

      final genre = item['genre']?.toString();
      final streamUrl = '$_baseUrl/tracks/$id/stream?app_name=CorePlayer';

      return Track(
        id: id,
        providerId: providerId,
        title: title,
        artist: artist,
        album: genre,
        artworkUrl: artworkUrl,
        duration: Duration(seconds: durationSec),
        genre: genre,
        isExplicit: false,
        isStreamable: true,
        isDownloadable: true,
        qualityOptions: const ['mp3'],
        sourceUrl: streamUrl,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Audius _mapToTrack error: $e');
      }
      return null;
    }
  }
}
