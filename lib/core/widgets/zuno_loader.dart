import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Draws the Zuno AI "spark" mark (the same shape used in the app icon and
/// watermark) as a vector path, so it stays crisp at any size and can be
/// animated without shipping a raster asset.
class _SparkPainter extends CustomPainter {
  final Color color;
  _SparkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // path is authored in a 24x24 box
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
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => oldDelegate.color != color;
}

/// Full-screen black loading state with the animated Zuno AI mark: a pulsing
/// spark inside expanding rings, with the wordmark fading in below. Use this
/// in place of a bare CircularProgressIndicator for any full-screen loading
/// moment (auth check, initial data load, etc).
class ZunoLoadingScreen extends StatefulWidget {
  const ZunoLoadingScreen({super.key});

  @override
  State<ZunoLoadingScreen> createState() => _ZunoLoadingScreenState();
}

class _ZunoLoadingScreenState extends State<ZunoLoadingScreen> with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _sparkController;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
    _sparkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ringController.dispose();
    _sparkController.dispose();
    super.dispose();
  }

  Widget _ring(double delay) {
    return AnimatedBuilder(
      animation: _ringController,
      builder: (context, _) {
        final t = (_ringController.value + delay) % 1.0;
        final scale = 0.85 + (t * 0.5);
        final opacity = t < 0.78 ? (1 - (t / 0.78)) * 0.55 : 0.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.electricLime, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _ring(0.0),
                  _ring(0.32),
                  _ring(0.64),
                  AnimatedBuilder(
                    animation: _sparkController,
                    builder: (context, child) {
                      final scale = 1.0 + (_sparkController.value * 0.12);
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CustomPaint(painter: _SparkPainter(AppColors.electricLime)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "zuno",
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.electricLime,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    "AI",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
