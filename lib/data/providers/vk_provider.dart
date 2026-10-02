import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class VkProvider implements MusicProvider {
  final String? accessToken;
  final String _version = '5.131';

  VkProvider({this.accessToken}); 

  @override
  String get providerId => 'vk';

  @override
  String get name => 'VK Music';

  @override
  Future<bool> authenticate() async {
    return accessToken != null && accessToken!.isNotEmpty;
  }

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    if (accessToken == null || accessToken!.isEmpty) {
      return []; // Если токена нет, просто ничего не возвращаем
    }

    final uri = Uri.parse('https://api.vk.com/method/audio.search').replace(queryParameters: {
      'access_token': accessToken,
      'v': _version,
      'q': query,
      'count': '30',
    });

    try {
      // VK API часто требует специфичный User-Agent для работы с аудио
      final response = await http.get(uri, headers: {
        'User-Agent': 'KateMobileAndroid/56 lite-460 (Android 4.4.2; SDK 19; x86; unknown Android SDK built for x86; en)'
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data.containsKey('error')) {
          print('VK API Error: ${data['error']}');
          return [];
        }

        final items = data['response']['items'] as List;
        return items.map((json) => _mapToTrack(json)).toList();
      }
    } catch (e) {
      print('VK Search failed: $e');
    }
    
    return [];
  }

  @override
  Future<Track?> getTrack(String id) async {
    return null; // Для получения конкретного трека нужен audio.getById
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    if (accessToken == null) throw Exception('VK playback requires Auth Token');
    // В VK url может быть привязан к IP, поэтому его нужно брать свежим, 
    // но для начала попробуем использовать тот, что пришел в поиске.
    if (track.sourceUrl.isEmpty) {
      throw Exception('Stream URL is empty');
    }
    return track.sourceUrl;
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    // В зависимости от того, m3u8 это или mp3
    if (track.sourceUrl.contains('.mp3')) {
      return ['mp3'];
    }
    return [];
  }

  @override
  Future<List<Track>> getUserLibrary() async {
    return []; // Реализуется через audio.get
  }

  Track _mapToTrack(Map<String, dynamic> json) {
    // VK отдает url, но иногда он бывает m3u8 (HLS), который just_audio умеет играть
    return Track(
      id: '${json['owner_id']}_${json['id']}',
      providerId: providerId,
      title: json['title'] ?? 'Unknown',
      artist: json['artist'] ?? 'Unknown',
      duration: Duration(seconds: json['duration'] ?? 0),
      isExplicit: json['is_explicit'] == true,
      isStreamable: json['url'] != null && json['url'].toString().isNotEmpty,
      isDownloadable: json['url'] != null && json['url'].toString().contains('.mp3'),
      sourceUrl: json['url'] ?? '',
    );
  }
}
