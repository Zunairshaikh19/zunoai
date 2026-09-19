import 'package:flutter/material.dart';

class _BadgeSparkPainter extends CustomPainter {
  final Color color;
  _BadgeSparkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // path authored in a 24x24 box
    final path = Path()
      ..moveTo(12 * s, 1 * s)
      ..cubicTo(12.8 * s, 7.5 * s, 16.5 * s, 11.2 * s, 23 * s, 12 * s)
      ..cubicTo(16.5 * s, 12.8 * s, 12.8 * s, 16.5 * s, 12 * s, 23 * s)
      ..cubicTo(11.2 * s, 16.5 * s, 7.5 * s, 12.8 * s, 1 * s, 12 * s)
      ..cubicTo(7.5 * s, 11.2 * s, 11.2 * s, 7.5 * s, 12 * s, 1 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BadgeSparkPainter oldDelegate) => oldDelegate.color != color;
}

/// The small on-screen brand watermark shown over a free-tier preview —
/// mirrors the mark baked into the actual downloaded/shared file by
/// applyWatermark() in core/utils/watermark.dart, so what the user sees
/// on screen matches what they'll get in the saved file.
class ZunoWatermarkBadge extends StatelessWidget {
  const ZunoWatermarkBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CustomPaint(painter: _BadgeSparkPainter(Colors.white))),
          const SizedBox(width: 6),
          const Text(
            "Zuno AI",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
