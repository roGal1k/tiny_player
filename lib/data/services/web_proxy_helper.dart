import 'package:flutter/foundation.dart';

/// Helper to handle CORS restrictions and stream forwarding when running on Web.
/// On desktop and mobile platforms (Android/iOS/Linux), all URLs remain direct.
class WebProxyHelper {
  /// Base origin of the server (dynamically resolved on web from current page origin)
  static String get webOrigin {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && !origin.startsWith('file://')) {
          return origin;
        }
      } catch (_) {}
    }
    return 'http://galik-tech.su';
  }

  /// Transforms an audio stream URL into a CORS-enabled proxy stream URL when running on Web
  static String proxyStreamUrl(String url) {
    if (!kIsWeb) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
    if (url.contains('/api/proxy/stream')) return url;
    return '$webOrigin/api/proxy/stream?url=${Uri.encodeComponent(url)}';
  }

  /// Transforms an external HTTP request URL into a CORS-enabled proxy URL when running on Web
  static String proxyHttpUrl(String url) {
    if (!kIsWeb) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
    // Do not proxy requests already going to our own API server
    if (url.startsWith(webOrigin) || url.contains('/api/')) return url;
    return '$webOrigin/api/proxy/http?url=${Uri.encodeComponent(url)}';
  }

  /// Helper for Uri instances
  static Uri proxyUri(Uri uri) {
    if (!kIsWeb) return uri;
    return Uri.parse(proxyHttpUrl(uri.toString()));
  }
}
