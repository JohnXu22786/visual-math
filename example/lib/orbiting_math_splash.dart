import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated startup cover driven by progress owned by the host application.
///
/// The orbit continues indefinitely until [progress] reaches 1.0. At that
/// point the cover scales up and fades out together over one second.
class OrbitingMathSplash extends StatefulWidget {
  const OrbitingMathSplash({
    super.key,
    required this.progress,
    this.onTransitionComplete,
  });

  final double progress;
  final VoidCallback? onTransitionComplete;

  @override
  State<OrbitingMathSplash> createState() => _OrbitingMathSplashState();
}

class _OrbitingMathSplashState extends State<OrbitingMathSplash>
    with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  bool _isExiting = false;
  bool _hasNotifiedCompletion = false;

  @override
  void initState() {
    super.initState();
    _exit.addListener(_handleExitProgress);
    _orbit.repeat();
    if (widget.progress >= 1) _beginExit();
  }

  @override
  void didUpdateWidget(covariant OrbitingMathSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress >= 1) _beginExit();
  }

  void _beginExit() {
    if (_isExiting) return;
    _isExiting = true;
    _orbit.stop();
    _exit.forward();
  }

  @override
  void dispose() {
    _exit.removeListener(_handleExitProgress);
    _orbit.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_orbit, _exit]),
    builder: (context, _) {
      final t = Curves.easeInCubic.transform(_exit.value);
      return IgnorePointer(
        child: Transform.scale(
          alignment: Alignment.center,
          scale: 1 + 2.35 * t,
          child: Opacity(
            opacity: 1 - t,
            child: _SplashScene(angle: _orbit.value * math.pi * 2),
          ),
        ),
      );
    },
  );

  void _handleExitProgress() {
    if (_exit.value >= 1 && !_hasNotifiedCompletion) {
      _hasNotifiedCompletion = true;
      widget.onTransitionComplete?.call();
    }
  }
}

const _mint = Color(0xFF72E8D7);
const _violet = Color(0xFFA293FF);
const _amber = Color(0xFFFFC37A);

class _SplashScene extends StatelessWidget {
  const _SplashScene({required this.angle});

  final double angle;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(.02, -.16),
        radius: 1.05,
        colors: [Color(0xFF111D38), Color(0xFF071020), Color(0xFF050914)],
        stops: [0, .58, 1],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _BackdropPainter()),
        CustomPaint(painter: _OrbitPainter(angle)),
      ],
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.angle);

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height * .425);
    final radius = shortest * .285;
    const orbitColors = [_mint, _violet, _amber];
    for (var lane = 0; lane < orbitColors.length; lane++) {
      final rotation = angle * .12 + lane * math.pi / 3;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 2,
          height: radius * .78,
        ),
        Paint()
          ..color = orbitColors[lane].withValues(alpha: .82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      canvas.restore();
    }

    const symbols = ['π', '√', '∞', 'x²', '∫', 'Δ'];
    for (var i = 0; i < symbols.length; i++) {
      final phase = angle + i * math.pi / 3;
      final tokenOrbitRadius = radius * 1.02;
      _drawToken(
        canvas,
        center +
            Offset(
              tokenOrbitRadius * math.cos(phase),
              tokenOrbitRadius * math.sin(phase),
            ),
        symbols[i],
      );
    }

    _drawCore(canvas, center, shortest);
  }

  void _drawToken(Canvas canvas, Offset center, String symbol) {
    const tokenRadius = 25.0;
    canvas.drawCircle(
      center,
      tokenRadius,
      Paint()..color = const Color(0xFF101D38),
    );
    canvas.drawCircle(
      center,
      tokenRadius,
      Paint()
        ..color = const Color(0xCC9BE7EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _drawText(canvas, symbol, center, 21, const Color(0xFFF0F8FF));
  }

  void _drawCore(Canvas canvas, Offset center, double shortest) {
    final coreRadius = shortest * .073;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        coreRadius + i * 7,
        Paint()
          ..color = _amber.withValues(alpha: .82 - i * .19)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawCircle(
      center,
      coreRadius - 2,
      Paint()..color = const Color(0xFF0C1730),
    );
    _drawText(canvas, '∑', center, shortest * .095, const Color(0xFFFFE2AC));
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.angle != angle;
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x1878A6D1)
      ..strokeWidth = 1;
    for (var x = 48.0; x < size.width; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 48.0; y < size.height; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final starPaint = Paint()..color = const Color(0x557DAFC8);
    for (var i = 0; i < 42; i++) {
      final x = ((i * 197 + 31) % 997) / 997 * size.width;
      final y = ((i * 89 + 23) % 991) / 991 * size.height;
      canvas.drawCircle(Offset(x, y), i % 5 == 0 ? 1.8 : 1.1, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}
