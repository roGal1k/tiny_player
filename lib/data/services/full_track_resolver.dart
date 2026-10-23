import 'package:flutter/foundation.dart';
import '../../domain/models/track.dart';
import '../providers/provider_registry.dart';
import '../providers/hitmo_provider.dart';
import '../providers/youtube_provider.dart';

class ResolvedTrackStream {
  final String streamUrl;
  final String effectiveSource; // e.g. 'hitmo_full', 'youtube_full', 'original'
  final bool isFullLength;

  const ResolvedTrackStream({
    required this.streamUrl,
    required this.effectiveSource,
    required this.isFullLength,
  });
}

class FullTrackResolver {
  final ProviderRegistry registry;

  FullTrackResolver({required this.registry});

  bool isPreviewTrack(Track track) {
    if (track.providerId == 'deezer') return true;
    if (track.sourceUrl.contains('cdns-preview-') || track.sourceUrl.contains('/preview/')) return true;
    // If provider duration is suspiciously exactly 30s while title is a real song
    if (track.duration.inSeconds == 30 && track.providerId != 'local') return true;
    return false;
  }

  /// Resolves the best possible stream URL for [track].
  /// If [track] is a 30-second snippet (e.g. Deezer preview),
  /// it queries full-track providers (Hitmo, then YouTube) to play the full song.
  Future<ResolvedTrackStream> resolveStream(Track track) async {
    // If not a preview track, get native stream directly
    if (!isPreviewTrack(track)) {
      final provider = registry.activeProviders.firstWhere(
        (p) => p.providerId == track.providerId,
        orElse: () => throw Exception('Provider ${track.providerId} not found'),
      );
      final url = await provider.getStreamUrl(track);
      return ResolvedTrackStream(
        streamUrl: url,
        effectiveSource: track.providerId,
        isFullLength: true,
      );
    }

    debugPrint('[FullTrackResolver] "${track.artist} - ${track.title}" is a 30s preview. Resolving full track...');

    // 1. Try Hitmo for full 320kbps MP3
    try {
      final hitmo = registry.activeProviders.whereType<HitmoProvider>().firstOrNull;
      if (hitmo != null) {
        final query = '${track.artist} ${track.title}'.trim();
        final hitmoResults = await hitmo.search(query).timeout(const Duration(milliseconds: 3000));
        
        // Find best match by comparing titles
        Track? bestMatch;
        final cleanTargetTitle = _cleanTitle(track.title);
        for (final ht in hitmoResults) {
          final htClean = _cleanTitle(ht.title);
          if (htClean == cleanTargetTitle || htClean.contains(cleanTargetTitle) || cleanTargetTitle.contains(htClean)) {
            bestMatch = ht;
            break;
          }
        }
        bestMatch ??= hitmoResults.isNotEmpty ? hitmoResults.first : null;

        if (bestMatch != null) {
          final hitmoUrl = await hitmo.getStreamUrl(bestMatch);
          if (hitmoUrl.isNotEmpty) {
            debugPrint('[FullTrackResolver] Successfully resolved full track via Hitmo: "${bestMatch.artist} - ${bestMatch.title}"');
            return ResolvedTrackStream(
              streamUrl: hitmoUrl,
              effectiveSource: 'hitmo',
              isFullLength: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[FullTrackResolver] Hitmo full-track resolution failed: $e');
    }

    // 2. Try YouTube for full audio stream
    try {
      final yt = registry.activeProviders.whereType<YouTubeProvider>().firstOrNull;
      if (yt != null) {
        final query = '${track.artist} - ${track.title}'.trim();
        final ytResults = await yt.search(query).timeout(const Duration(milliseconds: 3500));
        if (ytResults.isNotEmpty) {
          final ytMatch = ytResults.first;
          final ytUrl = await yt.getStreamUrl(ytMatch);
          if (ytUrl.isNotEmpty) {
            debugPrint('[FullTrackResolver] Successfully resolved full track via YouTube: "${ytMatch.artist} - ${ytMatch.title}"');
            return ResolvedTrackStream(
              streamUrl: ytUrl,
              effectiveSource: 'youtube',
              isFullLength: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[FullTrackResolver] YouTube full-track resolution failed: $e');
    }

    // 3. Fallback to original 30s preview
    final provider = registry.activeProviders.firstWhere(
      (p) => p.providerId == track.providerId,
      orElse: () => throw Exception('Provider ${track.providerId} not found'),
    );
    final fallbackUrl = await provider.getStreamUrl(track);
    debugPrint('[FullTrackResolver] No full version found for "${track.title}". Playing original preview.');
    return ResolvedTrackStream(
      streamUrl: fallbackUrl,
      effectiveSource: track.providerId,
      isFullLength: false,
    );
  }

  String _cleanTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove (feat...), [remix]
        .replaceAll(RegExp(r'[^\w\s\u0400-\u04FF]'), '') // keep alphanumeric and cyrillic
        .trim();
  }
}
