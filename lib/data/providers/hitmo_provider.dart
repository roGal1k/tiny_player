import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';

class HitmoProvider implements MusicProvider {
  String _mirrorUrl;
  final http.Client _client;

  HitmoProvider({
    String? mirrorUrl,
    http.Client? client,
  })  : _mirrorUrl = (mirrorUrl != null && mirrorUrl.isNotEmpty)
            ? mirrorUrl.replaceAll(RegExp(r'/+$'), '')
            : 'https://ru.hitmoz.org',
        _client = client ?? http.Client();

  String get mirrorUrl => _mirrorUrl;

  void updateMirrorUrl(String newUrl) {
    if (newUrl.trim().isNotEmpty) {
      _mirrorUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
  }

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'X-Forwarded-For': '85.249.20.1',
        'X-Real-IP': '85.249.20.1',
        'CF-Connecting-IP': '85.249.20.1',
      };

  final List<String> _fallbackMirrors = const [
    'https://ru.hitmoz.org',
    'https://rur.hitmotop.com',
  ];

  @override
  String get providerId => 'hitmo';

  @override
  String get name => 'Hitmo';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    if (query.trim().isEmpty) return [];

    final formattedQuery = query.trim().replaceAll(' ', '+');
    final searchUri = Uri.parse('$mirrorUrl/search?q=$formattedQuery');

    return _fetchTracksWithFallback(searchUri, '/search?q=$formattedQuery');
  }

  Future<List<Track>> getPopularTracks() async {
    final uri = Uri.parse('$mirrorUrl/songs/top-today');
    return _fetchTracksWithFallback(uri, '/songs/top-today');
  }

  Future<List<Track>> getNewTracks() async {
    final uri = Uri.parse('$mirrorUrl/songs/new');
    return _fetchTracksWithFallback(uri, '/songs/new');
  }

  Future<List<Track>> _fetchTracksWithFallback(Uri primaryUri, String pathAndQuery) async {
    final tracks = await _fetchTracksFromUrl(primaryUri);
    if (tracks.isNotEmpty) return tracks;

    // Пробуем запасные зеркала, если основное заблокировано или не вернуло треки
    for (final fallbackBase in _fallbackMirrors) {
      if (fallbackBase == mirrorUrl) continue;
      final fallbackUri = Uri.parse('$fallbackBase$pathAndQuery');
      final fallbackTracks = await _fetchTracksFromUrl(fallbackUri);
      if (fallbackTracks.isNotEmpty) return fallbackTracks;
    }

    return [];
  }

  Future<List<Track>> _fetchTracksFromUrl(Uri uri) async {
    try {
      final response = await _client.get(
        uri,
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return parseHtmlTracks(response.body, baseDomain: '${uri.scheme}://${uri.host}');
      }
    } catch (e) {
      // Graceful fallback on network timeout or blocked mirrors
    }

    return [];
  }

  List<Track> parseHtmlTracks(String html, {String? baseDomain}) {
    final doc = html_parser.parse(html);
    final trackElements = doc.querySelectorAll('div.track__info');
    final tracks = <Track>[];
    final activeBase = baseDomain ?? mirrorUrl;

    for (final el in trackElements) {
      final titleEl = el.querySelector('div.track__title');
      final artistEl = el.querySelector('div.track__desc');
      final durationEl = el.querySelector('div.track__fulltime');
      final downloadBtn = el.querySelector('a.track__download-btn');

      final title = titleEl?.text.trim() ?? 'Unknown Title';
      final artist = artistEl?.text.trim() ?? 'Unknown Artist';
      final durationText = durationEl?.text.trim() ?? '0:00';
      final streamUrl = downloadBtn?.attributes['href']?.trim() ?? '';

      if (streamUrl.isEmpty) continue;

      // Извлекаем обложку из data-musmeta родительского li
      String? artworkUrl;
      final parentEl = el.parent;
      final musMetaAttr = parentEl?.attributes['data-musmeta'];
      if (musMetaAttr != null && musMetaAttr.isNotEmpty) {
        try {
          final meta = json.decode(musMetaAttr);
          artworkUrl = meta['img']?.toString();
        } catch (_) {}
      }

      // Парсим длительность из "03:45"
      final parts = durationText.split(':');
      var duration = Duration.zero;
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        duration = Duration(minutes: m, seconds: s);
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        duration = Duration(hours: h, minutes: m, seconds: s);
      }

      final fullStreamUrl = streamUrl.startsWith('http')
          ? streamUrl
          : Uri.parse(activeBase).resolve(streamUrl).toString();

      tracks.add(
        Track(
          id: 'hitmo_${fullStreamUrl.hashCode.abs()}',
          providerId: providerId,
          title: title,
          artist: artist,
          album: 'Hitmo Music',
          artworkUrl: artworkUrl,
          duration: duration,
          isExplicit: false,
          isStreamable: true,
          isDownloadable: true,
          sourceUrl: fullStreamUrl,
        ),
      );
    }

    return tracks;
  }

  @override
  Future<Track?> getTrack(String id) async => null;

  @override
  Future<String> getStreamUrl(Track track) async {
    if (track.sourceUrl.isEmpty) {
      throw Exception('No stream URL available for Hitmo track');
    }

    try {
      final uri = Uri.parse(track.sourceUrl);
      final request = http.Request('GET', uri);
      request.followRedirects = false; // Перехватываем 302 Location к прямому CDN
      request.headers.addAll(_headers);

      final response = await _client.send(request).timeout(const Duration(seconds: 4));
      if (response.statusCode == 301 || response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          return location; // Прямая ссылка на CDN (например cdn20.deliciousoranges.com)
        }
      }
    } catch (_) {}

    return track.sourceUrl;
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async {
    return const ['mp3'];
  }

  @override
  Future<List<Track>> getUserLibrary() async => [];
}
