import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class SoundCloudProvider implements MusicProvider {
  final String? clientId;

  SoundCloudProvider({this.clientId}); 

  @override
  String get providerId => 'soundcloud';

  @override
  String get name => 'SoundCloud';

  @override
  Future<bool> authenticate() async {
    return clientId != null && clientId!.isNotEmpty;
  }

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    if (clientId == null || clientId!.isEmpty) {
      // Имитируем ответ, если нет ключа
      await Future.delayed(const Duration(milliseconds: 800));
      return [
        Track(
          id: 'sc_mock_1',
          providerId: providerId,
          title: '$query (SC Mock - Please add SC_CLIENT_ID to .env)',
          artist: 'SC Artist',
          duration: const Duration(minutes: 3, seconds: 45),
          isExplicit: false,
          isStreamable: false,
          isDownloadable: false,
          sourceUrl: '', 
        ),
      ];
    }

    // Настоящий запрос к API v2 SoundCloud
    final uri = Uri.parse('https://api-v2.soundcloud.com/search/tracks').replace(queryParameters: {
      'client_id': clientId,
      'q': query,
      'limit': '30',
    });

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final collection = data['collection'] as List;
        
        return collection.map((json) => _mapToTrack(json)).toList();
      } else {
        print('SoundCloud search failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('SoundCloud error: $e');
    }
    
    return [];
  }

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async {
    if (clientId == null) throw Exception('SoundCloud Client ID needed');
    if (track.sourceUrl.isEmpty) throw Exception('No stream URL available');

    // API v2 возвращает ссылку на транскодинг (плейлист m3u8 или прогрессивный mp3),
    // нам нужно сделать еще один запрос, чтобы получить итоговый URL потока.
    final uri = Uri.parse(track.sourceUrl).replace(queryParameters: {
      'client_id': clientId,
    });

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['url'] as String;
    }

    throw Exception('Failed to resolve SoundCloud stream URL');
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    if (track.isDownloadable) return ['mp3'];
    return [];
  }

  @override
  Future<List<Track>> getUserLibrary() async => [];

  Track _mapToTrack(Map<String, dynamic> json) {
    // Ищем доступный транскодинг: приоритет отдаем прямому mp3 (progressive),
    // затем незашифрованному hls. Зашифрованные cbc/ctr потоки пропускаем.
    String streamUrl = '';
    if (json['media'] != null && json['media']['transcodings'] != null) {
      final transcodings = (json['media']['transcodings'] as List)
          .cast<Map<String, dynamic>>();

      Map<String, dynamic>? selected;
      for (final item in transcodings) {
        final protocol = item['format']?['protocol']?.toString() ?? '';
        if (protocol == 'progressive') {
          selected = item;
          break; // Идеальный вариант найден
        }
        if (selected == null && protocol == 'hls' && !protocol.contains('encrypted')) {
          selected = item;
        }
      }

      if (selected != null) {
        streamUrl = selected['url']?.toString() ?? '';
      }
    }

    return Track(
      id: json['id'].toString(),
      providerId: providerId,
      title: json['title'] ?? 'Unknown',
      artist: json['user']?['username'] ?? 'Unknown',
      artworkUrl: json['artwork_url']?.toString().replaceAll('large', 't500x500'),
      duration: Duration(milliseconds: json['duration'] ?? 0),
      isExplicit: false,
      isStreamable: streamUrl.isNotEmpty,
      isDownloadable: streamUrl.isNotEmpty,
      sourceUrl: streamUrl,
    );
  }
}
