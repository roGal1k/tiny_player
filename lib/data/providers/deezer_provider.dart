import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/web_proxy_helper.dart';
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class DeezerProvider implements MusicProvider {
  final http.Client _client;
  final String? arl;
  final String _baseUrl = 'https://api.deezer.com';

  DeezerProvider({
    http.Client? client,
    this.arl,
  }) : _client = client ?? http.Client();

  @override
  String get providerId => 'deezer';

  @override
  String get name => 'Deezer';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': cleanQuery,
      'limit': '30',
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
          print('Deezer search error: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Deezer search exception: $e');
      }
    }
    return [];
  }

  @override
  Future<Track?> getTrack(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;

    final uri = Uri.parse('$_baseUrl/track/$cleanId');

    try {
      final response = await _client.get(WebProxyHelper.proxyUri(uri));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic> && decoded['id'] != null) {
          return _mapToTrack(decoded);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Deezer getTrack exception for $id: $e');
      }
    }
    return null;
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    if (track.sourceUrl.isNotEmpty) {
      return track.sourceUrl;
    }

    final freshTrack = await getTrack(track.id);
    if (freshTrack != null && freshTrack.sourceUrl.isNotEmpty) {
      return freshTrack.sourceUrl;
    }

    throw Exception('No playable stream URL found for Deezer track ${track.id}');
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
      final artistObj = item['artist'] as Map<String, dynamic>?;
      final artist = artistObj?['name']?.toString() ?? 'Unknown Artist';

      final albumObj = item['album'] as Map<String, dynamic>?;
      final album = albumObj?['title']?.toString();

      final artworkUrl = albumObj?['cover_big']?.toString() ??
          albumObj?['cover_medium']?.toString() ??
          item['album']?['cover']?.toString() ??
          artistObj?['picture_medium']?.toString();

      final durationSec = item['duration'] is num
          ? (item['duration'] as num).toInt()
          : int.tryParse(item['duration']?.toString() ?? '0') ?? 0;

      final previewUrl = item['preview']?.toString() ?? '';

      return Track(
        id: id,
        providerId: providerId,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: Duration(seconds: durationSec),
        isExplicit: item['explicit_lyrics'] == true,
        isStreamable: previewUrl.isNotEmpty,
        isDownloadable: previewUrl.isNotEmpty,
        qualityOptions: const ['mp3'],
        sourceUrl: previewUrl,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Deezer _mapToTrack error: $e');
      }
      return null;
    }
  }
}
