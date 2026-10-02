import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/equalizer_service.dart';
import '../../domain/models/equalizer_preset.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.90,
        child: EqualizerScreen(),
      ),
    );
  }

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final accentColor = eq.isEnabled ? Colors.tealAccent : Colors.white38;

    return Scaffold(
      backgroundColor: const Color(0xFF121318),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181A22),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tune, color: accentColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ЭКВАЛАЙЗЕР & ТЮНЕР',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'DSP Sound Engine • AIMP Style',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Мастер-тумблер ВКЛ / ВЫКЛ со светодиодным индикатором
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Text(
                  eq.isEnabled ? 'ВКЛ' : 'ВЫКЛ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: eq.isEnabled ? Colors.tealAccent : Colors.white38,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: eq.isEnabled,
                  activeColor: Colors.tealAccent,
                  activeTrackColor: Colors.tealAccent.withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.white24,
                  inactiveTrackColor: Colors.white10,
                  onChanged: (val) => eq.toggleEnabled(val),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          indicatorWeight: 3,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'ЭКВАЛАЙЗЕР (10 ПОЛОС)'),
            Tab(text: 'ТЮНЕР И ЭФФЕКТЫ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEqualizerTab(eq),
          _buildTunerTab(eq),
        ],
      ),
    );
  }

  // --- Вкладка 1: 10-полосный эквалайзер ---
  Widget _buildEqualizerTab(EqualizerService eq) {
    return Column(
      children: [
        // Панель пресетов и кнопок управления
        _buildPresetsBar(eq),

        // Кривая АЧХ (Частотный график Безье)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0C0D12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: eq.isEnabled
                    ? Colors.tealAccent.withValues(alpha: 0.3)
                    : Colors.white10,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _EqCurvePainter(
                  gains: eq.bandGains,
                  isEnabled: eq.isEnabled,
                ),
              ),
            ),
          ),
        ),

        // Сетка фейдеров (Preamp + 10 частотных полос)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                // Ползунок Preamp
                _buildPreampFader(eq),
                const VerticalDivider(width: 16, thickness: 1, color: Colors.white12),

                // 10 полос эквалайзера
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(10, (index) {
                          return _buildBandFader(eq, index);
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsBar(EqualizerService eq) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF161820),
      child: Row(
        children: [
          const Icon(Icons.tune_outlined, size: 16, color: Colors.white60),
          const SizedBox(width: 8),
          const Text('Пресет: ', style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(width: 4),

          // Выпадающий список пресетов
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: eq.allPresets.any((p) => p.name == eq.currentPresetName)
                    ? eq.currentPresetName
                    : 'Custom',
                isExpanded: true,
                dropdownColor: const Color(0xFF1E212B),
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                items: [
                  ...eq.allPresets.map((preset) {
                    return DropdownMenuItem<String>(
                      value: preset.name,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(preset.name),
                          if (preset.isCustom)
                            const Text(
                              'пользовательский',
                              style: TextStyle(fontSize: 10, color: Colors.white38),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (!eq.allPresets.any((p) => p.name == eq.currentPresetName))
                    const DropdownMenuItem<String>(
                      value: 'Custom',
                      child: Text('Custom (изменён)'),
                    ),
                ],
                onChanged: (selectedName) {
                  if (selectedName == null || selectedName == 'Custom') return;
                  final found = eq.allPresets.firstWhere(
                    (p) => p.name == selectedName,
                    orElse: () => EqualizerPreset.defaultPresets.first,
                  );
                  eq.applyPreset(found);
                },
              ),
            ),
          ),

          // Кнопка сохранения пресета
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: Colors.white70),
            tooltip: 'Сохранить пресет',
            onPressed: () => _showSavePresetDialog(context, eq),
          ),

          // Кнопка сброса в Flat (0 dB)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white70),
            tooltip: 'Сброс (Flat)',
            onPressed: eq.resetToFlat,
          ),
        ],
      ),
    );
  }

  Widget _buildPreampFader(EqualizerService eq) {
    return Column(
      children: [
        Text(
          '${eq.preampDb >= 0 ? "+" : ""}${eq.preampDb.toStringAsFixed(1)}',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: eq.isEnabled ? Colors.orangeAccent : Colors.white38,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: eq.isEnabled ? Colors.orangeAccent : Colors.white38,
                activeTrackColor: eq.isEnabled ? Colors.orangeAccent : Colors.white24,
                inactiveTrackColor: Colors.white12,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: eq.preampDb,
                min: -12.0,
                max: 12.0,
                onChanged: eq.isEnabled ? (val) => eq.setPreamp(val) : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Preamp',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
        ),
      ],
    );
  }

  Widget _buildBandFader(EqualizerService eq, int index) {
    final gain = eq.bandGains[index];
    final label = EqualizerPreset.frequencyLabels[index];
    final isBoosted = gain > 0;
    final isCut = gain < 0;

    final gainColor = eq.isEnabled
        ? (isBoosted
            ? Colors.tealAccent
            : (isCut ? Colors.pinkAccent : Colors.white70))
        : Colors.white24;

    return Flexible(
      child: Column(
        children: [
          // Значение dB над ползунком
          Text(
            '${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: gainColor,
            ),
          ),
          const SizedBox(height: 4),

          // Вертикальный слайдер
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbColor: eq.isEnabled ? Colors.tealAccent : Colors.white38,
                  activeTrackColor: eq.isEnabled ? Colors.tealAccent : Colors.white24,
                  inactiveTrackColor: Colors.white12,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: gain,
                  min: -12.0,
                  max: 12.0,
                  onChanged: eq.isEnabled
                      ? (val) {
                          // Округляем до 0.5 dB для приятного тактильного шага
                          final stepped = (val * 2).round() / 2;
                          eq.setBandGain(index, stepped);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Подпись частоты снизу
          Text(
            label.replaceAll(' ', ''),
            style: const TextStyle(
              fontSize: 9.5,
              color: Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Вкладка 2: Тюнер, Темп, Стереобаланс, Бас ---
  Widget _buildTunerTab(EqualizerService eq) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Карточка: Тюнер / Скорость и Темп
        _buildEffectCard(
          title: 'ТЮНЕР & ТЕМП ВОСПРОИЗВЕДЕНИЯ',
          icon: Icons.speed,
          subtitle: 'Регулировка скорости и тональности трека',
          valueText: '${eq.playbackRate.toStringAsFixed(2)}x',
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.tealAccent,
                  thumbColor: Colors.tealAccent,
                ),
                child: Slider(
                  value: eq.playbackRate,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: (val) => eq.setPlaybackRate(val),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0].map((rate) {
                  final isSelected = (eq.playbackRate - rate).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${rate}x'),
                    selected: isSelected,
                    onSelected: (_) => eq.setPlaybackRate(rate),
                    selectedColor: Colors.tealAccent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.tealAccent : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Карточка: Стерео-баланс каналов
        _buildEffectCard(
          title: 'СТЕРЕО-БАЛАНС КАНАЛОВ',
          icon: Icons.compare_arrows,
          subtitle: 'Смещение звука между левым и правым динамиком',
          valueText: _formatBalance(eq.balance),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('L (Левый)', style: TextStyle(color: eq.balance < 0 ? Colors.tealAccent : Colors.white54, fontSize: 11)),
                  TextButton(
                    onPressed: () => eq.setBalance(0.0),
                    child: const Text('По центру (0)', style: TextStyle(fontSize: 11)),
                  ),
                  Text('R (Правый)', style: TextStyle(color: eq.balance > 0 ? Colors.tealAccent : Colors.white54, fontSize: 11)),
                ],
              ),
              Slider(
                value: eq.balance,
                min: -1.0,
                max: 1.0,
                divisions: 20,
                activeColor: Colors.tealAccent,
                onChanged: (val) => eq.setBalance(val),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Карточка: Усиление Басов (Bass Boost)
        _buildEffectCard(
          title: 'УСИЛЕНИЕ БАСОВ (BASS BOOST)',
          icon: Icons.speaker,
          subtitle: 'Динамическое насыщение низких частот',
          valueText: '${(eq.bassBoost * 100).toInt()}%',
          child: Column(
            children: [
              Slider(
                value: eq.bassBoost,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                activeColor: Colors.pinkAccent,
                onChanged: eq.isEnabled ? (val) => eq.setBassBoost(val) : null,
              ),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ('0%', 0.0),
                  ('25%', 0.25),
                  ('50%', 0.5),
                  ('75%', 0.75),
                  ('100%', 1.0),
                ].map((item) {
                  final isSelected = (eq.bassBoost - item.$2).abs() < 0.05;
                  return ChoiceChip(
                    label: Text(item.$1),
                    selected: isSelected,
                    onSelected: eq.isEnabled ? (_) => eq.setBassBoost(item.$2) : null,
                    selectedColor: Colors.pinkAccent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.pinkAccent : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEffectCard({
    required String title,
    required IconData icon,
    required String subtitle,
    required String valueText,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueText,
                  style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _formatBalance(double bal) {
    if (bal.abs() < 0.05) return 'Центр';
    if (bal < 0) return 'Левый ${(bal.abs() * 100).toInt()}%';
    return 'Правый ${(bal * 100).toInt()}%';
  }

  Future<void> _showSavePresetDialog(BuildContext context, EqualizerService eq) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1E26),
        title: const Text('Сохранить пресет'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Название пресета (например: Мой Бас)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                eq.saveCustomPreset(name);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Пресет "$name" сохранён')),
                );
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Custom Painter для плавной кривой АЧХ (частотного графика)
class _EqCurvePainter extends CustomPainter {
  final List<double> gains;
  final bool isEnabled;

  _EqCurvePainter({required this.gains, required this.isEnabled});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerY = h / 2.0;

    // Отрисовка центральной оси (0 dB)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(w, centerY), gridPaint);

    if (gains.isEmpty) return;

    // Преобразуем 10 значений dB (-12 ... +12) в координаты точек (X, Y)
    final points = <Offset>[];
    final stepX = w / (gains.length - 1);

    for (int i = 0; i < gains.length; i++) {
      final x = i * stepX;
      // При выключенном EQ кривая плоская по центру
      final gain = isEnabled ? gains[i] : 0.0;
      // -12 dB -> низ (h), +12 dB -> верх (0)
      final y = centerY - (gain / 12.0) * (centerY - 8);
      points.add(Offset(x, y.clamp(4.0, h - 4.0)));
    }

    // Построение плавной Безье-кривой (Spline)
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // Заливка градиентом под кривой
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isEnabled
          ? [
              Colors.tealAccent.withValues(alpha: 0.35),
              Colors.tealAccent.withValues(alpha: 0.0),
            ]
          : [
              Colors.white10,
              Colors.transparent,
            ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Отрисовка основной линии кривой
    final linePaint = Paint()
      ..color = isEnabled ? Colors.tealAccent : Colors.white30
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Отрисовка светящихся контрольных точек на каждой полосе
    final dotPaint = Paint()
      ..color = isEnabled ? Colors.tealAccent : Colors.white38
      ..style = PaintingStyle.fill;

    for (final p in points) {
      canvas.drawCircle(p, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.isEnabled != isEnabled || oldDelegate.gains != gains;
  }
}
