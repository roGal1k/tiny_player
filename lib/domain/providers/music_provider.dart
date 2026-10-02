import '../models/track.dart';

abstract class MusicProvider {
  String get providerId;
  String get name;

  /// Authenticate the user if required by the provider.
  Future<bool> authenticate();

  /// Search for tracks based on query and optional filters.
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters});

  /// Get detailed track information by ID.
  Future<Track?> getTrack(String id);

  /// Get the actual stream URL for playback.
  Future<String> getStreamUrl(Track track);

  /// Get available download options (formats, qualities).
  Future<List<String>> getDownloadOptions(Track track);

  /// Get user's personal library/favorites from this provider.
  Future<List<Track>> getUserLibrary();
}
