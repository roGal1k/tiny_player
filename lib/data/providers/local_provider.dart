import '../../domain/models/track.dart';
import '../../domain/providers/music_provider.dart';
import '../local/database_helper.dart';

class LocalProvider implements MusicProvider {
  final DatabaseHelper _dbHelper;

  LocalProvider({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  @override
  String get providerId => 'local';

  @override
  String get name => 'Local Files';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query, {Map<String, dynamic>? filters}) async {
    return await _dbHelper.searchLocalTracks(query);
  }

  @override
  Future<Track?> getTrack(String id) async {
    final tracks = await _dbHelper.getAllTracks();
    return tracks.firstWhere((t) => t.id == id);
  }

  @override
  Future<String> getStreamUrl(Track track) async {
    return track.sourceUrl;
  }

  @override
  Future<List<String>> getDownloadOptions(Track track) async => [];

  @override
  Future<List<Track>> getUserLibrary() async {
    return await _dbHelper.getLibraryTracks();
  }
}
