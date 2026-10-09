import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../../data/services/local_library_service.dart';
import '../controllers/audio_player_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showScanDialog(BuildContext context) {
    final defaultPath = (!kIsWeb && Platform.environment['HOME'] != null)
        ? p.join(Platform.environment['HOME']!, 'Music')
        : '/home/gera/Music';

    final textController = TextEditingController(text: defaultPath);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.folder_open, color: Colors.deepPurpleAccent),
              SizedBox(width: 8),
              Text('Scan Folder'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter path to scan for MP3, FLAC, OGG, WAV files:'),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'Folder Path',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final path = textController.text.trim();
                Navigator.of(dialogCtx).pop();

                if (path.isNotEmpty) {
                  final libraryService = context.read<LocalLibraryService>();
                  final added = await libraryService.scanDirectory(path);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Scan complete: added $added tracks')),
                    );
                  }
                }
              },
              child: const Text('Start Scan'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryService = context.watch<LocalLibraryService>();
    final audioController = context.read<AudioPlayerController>();
    final currentTrackId = context.select<AudioPlayerController, String?>(
      (c) => c.currentTrack?.id,
    );
    final isPlaying = context.select<AudioPlayerController, bool>(
      (c) => c.isPlaying,
    );
    final tracks = libraryService.tracks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Library',
            onPressed: libraryService.loadLibrary,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Scan Music Folder',
            onPressed: () => _showScanDialog(context),
          ),
        ],
      ),
      body: libraryService.isScanning
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning music files...'),
                ],
              ),
            )
          : tracks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 72,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your local library is empty',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan music from your computer or download tracks from Search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _showScanDialog(context),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Scan Folder'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isCurrent = currentTrackId == track.id;

                    return ListTile(
                      selected: isCurrent,
                      selectedTileColor: Colors.white.withValues(alpha: 0.06),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isCurrent && isPlaying
                              ? Icons.graphic_eq
                              : Icons.music_note,
                          color: Colors.deepPurpleAccent,
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? Colors.deepPurpleAccent : null,
                        ),
                      ),
                      subtitle: Text(
                        '${track.artist} • ${p.basename(track.sourceUrl)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isCurrent && isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: isCurrent ? Colors.deepPurpleAccent : null,
                            ),
                            onPressed: () => audioController.playTrack(track, playlist: libraryService.tracks),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'remove') {
                                libraryService.removeTrack(track.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'remove',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Text('Remove from Library'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => audioController.playTrack(track, playlist: libraryService.tracks),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scan Folder',
        onPressed: () => _showScanDialog(context),
        child: const Icon(Icons.folder_open),
      ),
    );
  }
}
