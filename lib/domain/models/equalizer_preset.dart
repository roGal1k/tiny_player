class EqualizerPreset {
  final String name;
  final List<double> gains;
  final double preampDb;
  final bool isCustom;

  const EqualizerPreset({
    required this.name,
    required this.gains,
    this.preampDb = 0.0,
    this.isCustom = false,
  });

  static const List<String> frequencyLabels = [
    '31 Hz',
    '63 Hz',
    '125 Hz',
    '250 Hz',
    '500 Hz',
    '1 kHz',
    '2 kHz',
    '4 kHz',
    '8 kHz',
    '16 kHz',
  ];

  static const List<int> frequencyHz = [
    31,
    63,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  static const List<EqualizerPreset> defaultPresets = [
    EqualizerPreset(
      name: 'Flat',
      gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      preampDb: 0.0,
    ),
    EqualizerPreset(
      name: 'Rock',
      gains: [4.5, 3.5, 1.5, -1.0, -1.5, 1.0, 2.5, 4.0, 4.5, 5.0],
      preampDb: 1.0,
    ),
    EqualizerPreset(
      name: 'Pop',
      gains: [-1.5, 1.0, 3.0, 4.0, 3.5, 1.0, -1.0, -1.5, -1.5, -2.0],
      preampDb: 0.5,
    ),
    EqualizerPreset(
      name: 'Jazz',
      gains: [3.5, 2.5, 1.0, 1.5, -1.5, -1.5, 0.0, 1.5, 3.0, 4.0],
      preampDb: 0.0,
    ),
    EqualizerPreset(
      name: 'Classical',
      gains: [4.0, 3.5, 2.5, 2.0, -1.5, -1.5, 0.0, 2.0, 3.0, 3.5],
      preampDb: 0.0,
    ),
    EqualizerPreset(
      name: 'Club / Dance',
      gains: [0.0, 0.0, 2.0, 3.5, 3.5, 3.5, 2.0, 0.0, 0.0, 0.0],
      preampDb: 1.0,
    ),
    EqualizerPreset(
      name: 'Bass Boost',
      gains: [6.0, 5.0, 4.0, 2.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      preampDb: -1.0,
    ),
    EqualizerPreset(
      name: 'Treble Boost',
      gains: [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.5, 4.0, 5.5, 6.5],
      preampDb: 0.0,
    ),
    EqualizerPreset(
      name: 'Vocal',
      gains: [-1.5, -2.5, -1.5, 1.5, 4.0, 4.0, 3.0, 1.5, 0.0, -1.5],
      preampDb: 0.5,
    ),
    EqualizerPreset(
      name: 'Metal',
      gains: [4.0, 2.5, 0.0, 0.0, -2.5, -2.5, 0.0, 2.5, 4.5, 5.0],
      preampDb: 0.5,
    ),
    EqualizerPreset(
      name: 'Acoustic',
      gains: [3.5, 3.0, 1.5, 1.0, 1.5, 1.5, 2.5, 3.0, 2.5, 1.5],
      preampDb: 0.0,
    ),
    EqualizerPreset(
      name: 'Electronic',
      gains: [4.5, 4.0, 1.0, 0.0, -2.0, 2.0, 1.0, 1.5, 4.0, 4.5],
      preampDb: 0.5,
    ),
    EqualizerPreset(
      name: 'Party',
      gains: [5.5, 5.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.5, 5.5],
      preampDb: 0.0,
    ),
  ];

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'gains': gains,
      'preampDb': preampDb,
      'isCustom': isCustom ? 1 : 0,
    };
  }

  factory EqualizerPreset.fromMap(Map<String, dynamic> map) {
    return EqualizerPreset(
      name: map['name'] as String? ?? 'Custom',
      gains: (map['gains'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          List.filled(10, 0.0),
      preampDb: (map['preampDb'] as num?)?.toDouble() ?? 0.0,
      isCustom: (map['isCustom'] == 1 || map['isCustom'] == true),
    );
  }

  EqualizerPreset copyWith({
    String? name,
    List<double>? gains,
    double? preampDb,
    bool? isCustom,
  }) {
    return EqualizerPreset(
      name: name ?? this.name,
      gains: gains ?? List<double>.from(this.gains),
      preampDb: preampDb ?? this.preampDb,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}
