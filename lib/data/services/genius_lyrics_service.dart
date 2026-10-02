import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class GeniusLyricsService {
  String? accessToken;
  final String? clientId;
  final String? clientSecret;

  GeniusLyricsService({
    this.accessToken,
    this.clientId,
    this.clientSecret,
  });

  String _cleanTrackTitle(String title) {
    return title
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?(?:official|audio|video|lyrics|remaster|hd|4k).*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+-\s+.*$'), '')
        .replaceAll(RegExp(r'\b(?:ft|feat)\.?\s+.*$', caseSensitive: false), '')
        .trim();
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&#x27;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'");
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (clientId == null || clientSecret == null) return;

    try {
      final response = await http.post(
        Uri.parse('https://api.genius.com/oauth/token'),
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        accessToken = data['access_token'];
      }
    } catch (_) {}
  }

  Future<List<dynamic>> _searchGenius(String query) async {
    final searchUri = Uri.parse('https://api.genius.com/search').replace(queryParameters: {
      'q': query,
    });

    try {
      var response = await http.get(
        searchUri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 401) {
        await _refreshTokenIfNeeded();
        response = await http.get(
          searchUri,
          headers: {'Authorization': 'Bearer $accessToken'},
        );
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response']?['hits'] as List? ?? [];
      }
    } catch (_) {}

    return [];
  }

  Future<String?> getLyrics(String title, String artist) async {
    if (accessToken == null || accessToken!.isEmpty) {
      await _refreshTokenIfNeeded();
    }
    if (accessToken == null || accessToken!.isEmpty) return null;

    final cleanedTitle = _cleanTrackTitle(title);

    // Пробуем несколько вариантов поискового запроса для максимальной точности
    List<dynamic> hits = [];
    if (artist.isNotEmpty && artist != 'Unknown Artist') {
      hits = await _searchGenius('$artist $cleanedTitle');
    }
    if (hits.isEmpty) {
      hits = await _searchGenius(cleanedTitle);
    }
    if (hits.isEmpty && artist.isNotEmpty) {
      hits = await _searchGenius('$artist $title');
    }
    if (hits.isEmpty) {
      hits = await _searchGenius(title);
    }

    if (hits.isEmpty) return null;

    final songUrl = hits.first['result']?['url'] as String?;
    if (songUrl == null || songUrl.isEmpty) return null;

    try {
      // Загружаем HTML страницы песни
      final pageResponse = await http.get(
        Uri.parse(songUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (pageResponse.statusCode != 200) return null;

      final doc = html_parser.parse(pageResponse.body);
      final containers = doc.querySelectorAll('div[data-lyrics-container="true"]');

      if (containers.isNotEmpty) {
        final buffer = StringBuffer();
        for (final container in containers) {
          // Удаляем шапки "12 Contributors", рекламные блоки и рекомендации
          for (final exclude in container.querySelectorAll('[data-exclude-from-selection="true"]')) {
            exclude.remove();
          }
          // Заменяем теги переноса строк на реальные \n
          for (final br in container.querySelectorAll('br')) {
            br.replaceWith(dom.Text('\n'));
          }

          final text = container.text.trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
            buffer.writeln();
          }
        }

        var lyrics = buffer.toString().trim();
        lyrics = _decodeHtmlEntities(lyrics);

        // Дополнительная очистка от мусорных строк Contributors на старте
        lyrics = lyrics.replaceAll(RegExp(r'^\d+\s*Contributors.*?\n', caseSensitive: false), '');
        lyrics = lyrics.replaceAll(RegExp(r'^\d+\s*Contributors', caseSensitive: false), '');

        if (lyrics.isNotEmpty) {
          return lyrics.trim();
        }
      }

      // Запасной вариант для старого оформления Genius
      final oldLyricsDiv = doc.querySelector('.lyrics');
      if (oldLyricsDiv != null) {
        for (final br in oldLyricsDiv.querySelectorAll('br')) {
          br.replaceWith(dom.Text('\n'));
        }
        var lyrics = oldLyricsDiv.text.trim();
        lyrics = _decodeHtmlEntities(lyrics);
        if (lyrics.isNotEmpty) return lyrics;
      }
    } catch (_) {}

    return null;
  }
}
