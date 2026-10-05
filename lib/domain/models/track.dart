class Track {
  final String id;
  final String providerId; // identifier of the provider (e.g. 'soundcloud', 'local')
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration duration;
  final DateTime? releaseDate;
  final String? genre;
  final bool isExplicit;
  final bool isStreamable;
  final bool isDownloadable;
  final List<String> qualityOptions;
  final String sourceUrl; // actual path or stream url

  const Track({
    required this.id,
    required this.providerId,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    required this.duration,
    this.releaseDate,
    this.genre,
    this.isExplicit = false,
    this.isStreamable = true,
    this.isDownloadable = false,
    this.qualityOptions = const [],
    required this.sourceUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'provider_id': providerId,
      'title': title,
      'artist': artist,
      'album': album,
      'artwork_url': artworkUrl,
      'duration_ms': duration.inMilliseconds,
      'release_date': releaseDate?.toIso8601String(),
      'genre': genre,
      'is_explicit': isExplicit ? 1 : 0,
      'is_streamable': isStreamable ? 1 : 0,
      'is_downloadable': isDownloadable ? 1 : 0,
      'quality_options': qualityOptions.join(','),
      'source_url': sourceUrl,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      providerId: map['provider_id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String?,
      artworkUrl: map['artwork_url'] as String?,
      duration: Duration(milliseconds: map['duration_ms'] as int),
      releaseDate: map['release_date'] != null 
          ? DateTime.tryParse(map['release_date'] as String) 
          : null,
      genre: map['genre'] as String?,
      isExplicit: (map['is_explicit'] as int?) == 1,
      isStreamable: (map['is_streamable'] as int?) == 1,
      isDownloadable: (map['is_downloadable'] as int?) == 1,
      qualityOptions: (map['quality_options'] as String?)?.split(',') ?? [],
      sourceUrl: map['source_url'] as String,
    );
  }

  Track copyWith({
    String? id,
    String? providerId,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
    DateTime? releaseDate,
    String? genre,
    bool? isExplicit,
    bool? isStreamable,
    bool? isDownloadable,
    List<String>? qualityOptions,
    String? sourceUrl,
  }) {
    return Track(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      duration: duration ?? this.duration,
      releaseDate: releaseDate ?? this.releaseDate,
      genre: genre ?? this.genre,
      isExplicit: isExplicit ?? this.isExplicit,
      isStreamable: isStreamable ?? this.isStreamable,
      isDownloadable: isDownloadable ?? this.isDownloadable,
      qualityOptions: qualityOptions ?? this.qualityOptions,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          providerId == other.providerId;

  @override
  int get hashCode => id.hashCode ^ providerId.hashCode;
}
