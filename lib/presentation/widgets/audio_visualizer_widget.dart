import 'dart:math' as math;
import 'package:flutter/material.dart';

class AudioVisualizerWidget extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  final double height;
  final int barCount;

  const AudioVisualizerWidget({
    super.key,
    required this.color,
    required this.isPlaying,
    this.height = 36.0,
    this.barCount = 26,
  });

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _VisualizerPainter(
            animationValue: _controller.value,
            color: widget.color,
            isPlaying: widget.isPlaying,
            barCount: widget.barCount,
          ),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final bool isPlaying;
  final int barCount;

  _VisualizerPainter({
    required this.animationValue,
    required this.color,
    required this.isPlaying,
    required this.barCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width / (barCount * 1.6)).clamp(3.0, 7.0);
    final totalSpacing = size.width - (barCount * barWidth);
    final gap = totalSpacing / (barCount - 1);

    final paint = Paint()..isAntiAlias = true;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);

      double heightFactor;
      if (isPlaying) {
        // Multi-frequency harmonic synthesis
        final phase1 = animationValue * 2 * math.pi + (i * 0.45);
        final phase2 = animationValue * 4 * math.pi + (i * 0.25);
        final phase3 = animationValue * 1.5 * math.pi + (i * 0.7);

        final wave1 = math.sin(phase1).abs();
        final wave2 = math.cos(phase2).abs() * 0.6;
        final wave3 = math.sin(phase3).abs() * 0.4;

        // Middle bars tend to be higher for a classic bell/spectrum curve
        final bellCurve = 0.5 + 0.5 * math.sin((i / (barCount - 1)) * math.pi);
        heightFactor = ((wave1 + wave2 + wave3) / 2.0 * bellCurve).clamp(0.12, 1.0);
      } else {
        heightFactor = 0.1; // Resting height when paused
      }

      final barHeight = (size.height * heightFactor).clamp(4.0, size.height);
      final y = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      paint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color.withValues(alpha: 0.4),
          color,
        ],
      ).createShader(rect.outerRect);

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color;
  }
}
