import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class JamendoProvider implements MusicProvider {
  // Для продакшена ключ лучше выносить в .env файл
  final String clientId;
  final String _baseUrl = 'https://api.jamendo.com/v3.0';

  // Используем известный тестовый ключ для начала
  JamendoProvider({this.clientId = 'b6747d04'}); 

  @override
  String get providerId => 'jamendo';

  @override
  String get name => 'Jamendo';

  @override
  Future<bool> authenticate() async {
    // Для базового поиска и стриминга в Jamendo достаточно clientId.
    // OAuth нужен только для управления аккаунтом пользователя.
    return true;
  }

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    final uri = Uri.parse('$_baseUrl/tracks/').replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'search': query,
      'limit': '30',
      'include': 'musicinfo', // для жанров
    });

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      
      return results.map((json) => _mapToTrack(json)).toList();
    } else {
      throw Exception('Failed to search Jamendo: ${response.statusCode}');
    }
  }

  @override
  Future<Track?> getTrack(String id) async {
    final uri = Uri.parse('$_baseUrl/tracks/').replace(queryParameters: {
      'client_id': clientId,
      'format': 'json',
      'id': id,
    });

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      if (results.isNotEmpty) {
        return _mapToTrack(results.first);
      }
    }
    return null;
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    // В случае Jamendo, stream_url уже хранится в sourceUrl
    return track.sourceUrl;
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    if (track.isDownloadable) {
      return ['mp3'];
    }
    return [];
  }

  @override
  Future<List<Track>> getUserLibrary() async {
    // Без персонального OAuth токена возвращаем пустоту
    return [];
  }

  Track _mapToTrack(Map<String, dynamic> json) {
    // Jamendo возвращает audiodownload_allowed boolean
    final isDownloadAllowed = json['audiodownload_allowed'] == true;
    
    // Пытаемся вытащить жанр из musicinfo
    String? genre;
    if (json['musicinfo'] != null && json['musicinfo']['tags'] != null) {
      final tags = json['musicinfo']['tags']['genres'] as List?;
      if (tags != null && tags.isNotEmpty) {
        genre = tags.first.toString();
      }
    }

    return Track(
      id: json['id'].toString(),
      providerId: providerId,
      title: json['name'] ?? 'Unknown Title',
      artist: json['artist_name'] ?? 'Unknown Artist',
      album: json['album_name'],
      artworkUrl: json['image'],
      duration: Duration(seconds: (json['duration'] ?? 0) as int),
      releaseDate: json['releasedate'] != null 
          ? DateTime.tryParse(json['releasedate']) 
          : null,
      genre: genre,
      isExplicit: false, // Jamendo контент обычно безопасный
      isStreamable: true,
      isDownloadable: (json['audio'] != null && (json['audio'] as String).isNotEmpty),
      sourceUrl: json['audio'] ?? '',
      qualityOptions: const ['mp3'],
    );
  }
}
