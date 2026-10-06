import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/web_proxy_helper.dart';
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class InternetArchiveProvider implements MusicProvider {
  final String _baseUrl = 'https://archive.org';

  @override
  String get providerId => 'internet_archive';

  @override
  String get name => 'Internet Archive';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    // Search for audio items matching the query
    final uri = Uri.parse('$_baseUrl/advancedsearch.php').replace(queryParameters: {
      'q': 'mediatype:audio AND title:($query)',
      'fl[]': 'identifier,title,creator,length,date',
      'output': 'json',
      'rows': '15',
    });

    final response = await http.get(WebProxyHelper.proxyUri(uri));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final docs = data['response']['docs'] as List;
      
      return docs.map((json) => _mapToTrack(json)).toList();
    } else {
      throw Exception('Internet Archive search failed: ${response.statusCode}');
    }
  }

  @override
  Future<Track?> getTrack(String id) async {
    // This is a simplified fetch, normally you'd query the metadata endpoint
    return null; 
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    // Internet archive streaming requires hitting the metadata endpoint to find the actual file name.
    final uri = Uri.parse('$_baseUrl/metadata/${track.id}');
    final response = await http.get(WebProxyHelper.proxyUri(uri));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final files = data['files'] as List;
      
      // Find the first mp3 or ogg file
      for (var file in files) {
        final name = file['name'] as String;
        if (name.endsWith('.mp3') || name.endsWith('.ogg') || name.endsWith('.flac')) {
          return '$_baseUrl/download/${track.id}/$name';
        }
      }
    }
    throw Exception('No playable audio file found in Internet Archive item');
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    if (track.isDownloadable) {
      return ['mp3', 'ogg', 'flac']; // We approximate here, actual format depends on the item
    }
    return [];
  }

  @override
  Future<List<Track>> getUserLibrary() async => [];

  Track _mapToTrack(Map<String, dynamic> json) {
    // Parse length (usually comes as "MM:SS" or seconds)
    Duration duration = Duration.zero;
    if (json['length'] != null) {
      final lengthStr = json['length'].toString();
      if (lengthStr.contains(':')) {
        final parts = lengthStr.split(':');
        if (parts.length == 2) {
          duration = Duration(
            minutes: int.tryParse(parts[0]) ?? 0,
            seconds: int.tryParse(parts[1]) ?? 0,
          );
        }
      } else {
        duration = Duration(seconds: double.tryParse(lengthStr)?.round() ?? 0);
      }
    }

    return Track(
      id: json['identifier']?.toString() ?? '',
      providerId: providerId,
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['creator'] != null 
          ? (json['creator'] is List ? json['creator'].join(', ') : json['creator'].toString()) 
          : 'Unknown Creator',
      album: 'Internet Archive',
      duration: duration,
      releaseDate: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
      isExplicit: false,
      isStreamable: true,
      isDownloadable: true, // Archive.org is almost always downloadable
      sourceUrl: '', // Will be resolved dynamically in getStreamUrl
    );
  }
}
