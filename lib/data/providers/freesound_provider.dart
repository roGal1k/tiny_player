import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class FreesoundProvider implements MusicProvider {
  final String? apiKey;
  final String _baseUrl = 'https://freesound.org/apiv2';

  FreesoundProvider({this.apiKey});

  @override
  String get providerId => 'freesound';

  @override
  String get name => 'Freesound';

  @override
  Future<bool> authenticate() async {
    return apiKey != null && apiKey!.isNotEmpty;
  }

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    if (apiKey == null || apiKey!.isEmpty) {
      return [];
    }

    final uri = Uri.parse('$_baseUrl/search/text/').replace(queryParameters: {
      'query': query,
      'token': apiKey,
      'fields': 'id,name,username,duration,previews,images',
      'page_size': '30',
    });

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List? ?? [];
        return results.map((item) => _mapToTrack(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      // Return empty on network or parse failure
    }

    return [];
  }

  @override
  Future<Track?> getTrack(String id) async {
    return null;
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    if (track.sourceUrl.isNotEmpty) {
      return track.sourceUrl;
    }
    throw Exception('No audio preview available for Freesound track ${track.id}');
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    if (track.isDownloadable) {
      return ['mp3'];
    }
    return [];
  }

  @override
  Future<List<Track>> getUserLibrary() async => [];

  Track _mapToTrack(Map<String, dynamic> json) {
    final previews = json['previews'] as Map<String, dynamic>?;
    final streamUrl = previews?['preview-hq-mp3']?.toString() ??
        previews?['preview-lq-mp3']?.toString() ??
        '';

    final images = json['images'] as Map<String, dynamic>?;
    final artworkUrl = images?['spectral_m']?.toString() ??
        images?['waveform_m']?.toString();

    final durationSeconds = (json['duration'] as num?)?.toDouble() ?? 0.0;

    return Track(
      id: 'fs_${json['id']}',
      providerId: providerId,
      title: json['name']?.toString() ?? 'Sound ${json['id']}',
      artist: json['username']?.toString() ?? 'Freesound Creator',
      album: 'Freesound Library',
      artworkUrl: artworkUrl,
      duration: Duration(milliseconds: (durationSeconds * 1000).toInt()),
      isExplicit: false,
      isStreamable: streamUrl.isNotEmpty,
      isDownloadable: streamUrl.isNotEmpty,
      qualityOptions: const ['mp3'],
      sourceUrl: streamUrl,
    );
  }
}
