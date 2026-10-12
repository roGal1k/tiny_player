class Artist {
  final String name;
  final String? artworkUrl;
  final DateTime addedAt;
  final int? trackCount;
  final String? providerId;

  const Artist({
    required this.name,
    this.artworkUrl,
    required this.addedAt,
    this.trackCount,
    this.providerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'artwork_url': artworkUrl,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      name: map['name'] as String? ?? 'Unknown Artist',
      artworkUrl: map['artwork_url'] as String?,
      addedAt: map['added_at'] != null 
          ? (DateTime.tryParse(map['added_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      trackCount: map['track_count'] as int?,
      providerId: map['provider_id'] as String?,
    );
  }

  Artist copyWith({
    String? name,
    String? artworkUrl,
    DateTime? addedAt,
    int? trackCount,
    String? providerId,
  }) {
    return Artist(
      name: name ?? this.name,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      addedAt: addedAt ?? this.addedAt,
      trackCount: trackCount ?? this.trackCount,
      providerId: providerId ?? this.providerId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artist &&
          runtimeType == other.runtimeType &&
          name.toLowerCase() == other.name.toLowerCase();

  @override
  int get hashCode => name.toLowerCase().hashCode;

  @override
  String toString() => 'Artist(name: $name, artworkUrl: $artworkUrl, count: $trackCount)';
}
