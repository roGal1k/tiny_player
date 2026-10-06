import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import '../../domain/models/track.dart';

class WebMediaSessionHelper {
  static void updateMetadata(Track track) {
    try {
      final session = html.window.navigator.mediaSession;
      if (session == null) return;
      session.metadata = html.MediaMetadata({
        'title': track.title,
        'artist': track.artist,
        'album': track.album ?? '',
        'artwork': track.artworkUrl != null && track.artworkUrl!.isNotEmpty
            ? [
                {'src': track.artworkUrl, 'sizes': '512x512', 'type': 'image/jpeg'}
              ]
            : [],
      });
    } catch (_) {}
  }

  static void setActionHandlers({
    void Function()? onPlay,
    void Function()? onPause,
    void Function()? onPrevious,
    void Function()? onNext,
    void Function(Duration)? onSeek,
  }) {
    try {
      final session = html.window.navigator.mediaSession;
      if (session == null) return;
      if (onPlay != null) session.setActionHandler('play', onPlay);
      if (onPause != null) session.setActionHandler('pause', onPause);
      if (onPrevious != null) session.setActionHandler('previoustrack', onPrevious);
      if (onNext != null) session.setActionHandler('nexttrack', onNext);
      if (onSeek != null) {
        try {
          js_util.callMethod(session, 'setActionHandler', [
            'seekto',
            js.allowInterop((details) {
              try {
                final seekTime = js_util.getProperty(details, 'seekTime');
                if (seekTime is num) {
                  onSeek(Duration(milliseconds: (seekTime * 1000).toInt()));
                }
              } catch (_) {}
            }),
          ]);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
