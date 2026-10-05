import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/audio_cache_service.dart';
import '../controllers/audio_player_controller.dart';
import '../../domain/models/track.dart';

class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Color _getProviderColor(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'hitmo':
        return Colors.pinkAccent;
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'audius':
        return const Color(0xFFCC0FE0);
      case 'deezer':
        return const Color(0xFFFEAA2D);
      case 'soundcloud':
        return Colors.orangeAccent;
      case 'jamendo':
        return Colors.redAccent;
      case 'internet_archive':
        return Colors.blueAccent;
      case 'vk':
        return Colors.lightBlueAccent;
      case 'freesound':
        return Colors.tealAccent;
      default:
        return Colors.deepPurpleAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cacheService = context.watch<AudioCacheService?>();
    final audioController = context.watch<AudioPlayerController>();

    if (cacheService == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Офлайн-кэш', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: const Center(child: Text('Кэш-сервис не инициализирован')),
      );
    }

    final totalBytes = cacheService.totalCacheSizeBytes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Офлайн-кэш', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'Очистить кэш',
            onPressed: () => _confirmClearCache(context, cacheService),
          ),
        ],
      ),
      body: FutureBuilder<List<Track>>(
        future: cacheService.getCachedTracks(),
        builder: (context, snapshot) {
          final allTracks = snapshot.data ?? [];
          final tracks = _filterQuery.isEmpty
              ? allTracks
              : allTracks.where((t) {
                  final q = _filterQuery.toLowerCase();
                  return t.title.toLowerCase().contains(q) ||
                      t.artist.toLowerCase().contains(q) ||
                      (t.album != null && t.album!.toLowerCase().contains(q));
                }).toList();

          if (allTracks.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.offline_pin_outlined,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Офлайн-кэш пуст',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Слушайте любые треки в поиске — они будут автоматически сохраняться сюда на диск для мгновенного доступа без интернета.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              // Summary Banner Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.offline_pin, size: 22, color: Colors.greenAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${allTracks.length} закэшированных треков',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Общий размер на диске: ${_formatBytes(totalBytes)}',
                                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            if (tracks.isNotEmpty) {
                              audioController.playTrack(tracks.first, playlist: tracks);
                            }
                          },
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Слушать все'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.shuffle, size: 20),
                          tooltip: 'Случайно',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (tracks.isNotEmpty) {
                              final shuffled = List<Track>.from(tracks)..shuffle();
                              audioController.playTrack(shuffled.first, playlist: shuffled);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Search in Cache
                    TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setState(() {
                          _filterQuery = val.trim();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Поиск по закэшированным трекам...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _filterQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _filterQuery = '';
                                  });
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),

              // Tracks List
              Expanded(
                child: tracks.isEmpty
                    ? Center(
                        child: Text(
                          'Ничего не найдено по запросу "$_filterQuery"',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final isCurrent = audioController.currentTrack?.id == track.id &&
                              audioController.currentTrack?.providerId == track.providerId;
                          final providerColor = _getProviderColor(track.providerId);

                          int? fileSize;
                          if (track.sourceUrl.isNotEmpty) {
                            try {
                              final f = File(track.sourceUrl);
                              if (f.existsSync()) fileSize = f.lengthSync();
                            } catch (_) {}
                          }

                          return ListTile(
                            selected: isCurrent,
                            selectedTileColor: Colors.white.withValues(alpha: 0.06),
                            leading: Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                                      ? Image.network(
                                          track.artworkUrl!,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => Container(
                                            width: 48,
                                            height: 48,
                                            color: Colors.white12,
                                            child: const Icon(Icons.music_note),
                                          ),
                                        )
                                      : Container(
                                          width: 48,
                                          height: 48,
                                          color: Colors.white12,
                                          child: const Icon(Icons.music_note),
                                        ),
                                ),
                                if (isCurrent && audioController.isPlaying)
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(Icons.graphic_eq, color: providerColor, size: 26),
                                  ),
                              ],
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                color: isCurrent ? providerColor : null,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: providerColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    track.providerId.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: providerColor,
                                    ),
                                  ),
                                ),
                                if (fileSize != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatBytes(fileSize),
                                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (track.duration > Duration.zero)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      _formatDuration(track.duration),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.55),
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    isCurrent && audioController.isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    color: isCurrent ? providerColor : Colors.greenAccent,
                                    size: 28,
                                  ),
                                  tooltip: 'Воспроизвести офлайн',
                                  onPressed: () {
                                    audioController.playTrack(track, playlist: tracks);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white60),
                                  tooltip: 'Удалить из кэша',
                                  onPressed: () async {
                                    await cacheService.removeTrackFromCache(track);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              audioController.playTrack(track, playlist: tracks);
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClearCache(BuildContext context, AudioCacheService cacheService) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить офлайн-кэш?'),
        content: const Text('Все закэшированные треки будут удалены с диска.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await cacheService.clearCache();
      setState(() {});
    }
  }
}
