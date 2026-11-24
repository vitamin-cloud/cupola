import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// This fork's ("Stack") glass: the Living Room Remote's, one recipe for every
/// card in the app.
///
/// A dense navy frost (no live blur, so it reads the same in every frame of a
/// scroll or a fade), a white sheen from the top, a 1.5px white rim with a
/// brighter top edge, and a soft drop shadow.
///
/// [glow] lights it the way the remote lights the app it last opened: the
/// colour washes the glass, the rim takes it, and it blooms around the edge.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.glow,
    this.glowStrength = 1,
    this.shadow = true,
    this.clip = true,
  });

  final Widget child;
  final double radius;

  /// A brand colour to glow with, or null for plain glass.
  final Color? glow;

  /// 0..1, how strongly [glow] shows: the remote softens the loud reds and
  /// yellows (YouTube's at 0.65).
  final double glowStrength;

  /// Whether to cast the drop shadow (off for a panel inside another).
  final bool shadow;

  /// Whether [child] is clipped to the rounded shape.
  final bool clip;

  /// The remote's glass as it reads over the photo, flattened: dense enough
  /// to stand in for its blur.
  static const Color tint = Color(0xD0141A2E);

  /// The rim and its brighter top edge.
  static const Color rim = Color(0x38FFFFFF);
  static const Color rimTop = Color(0x2EFFFFFF);

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final g = glow;
    final k = glowStrength.clamp(0.0, 1.0);
    final sheen = BoxDecoration(
      borderRadius: shape,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.55, 1],
        colors: g == null
            ? const [Color(0x29FFFFFF), Color(0x0DFFFFFF), Color(0x14FFFFFF)]
            : [
                g.withValues(alpha: 0.34 * k),
                g.withValues(alpha: 0.22 * k),
                g.withValues(alpha: 0.16 * k),
              ],
      ),
    );
    final border = BoxDecoration(
      borderRadius: shape,
      border: Border.all(
        color: g == null ? rim : g.withValues(alpha: 0.9),
        width: 1.5,
      ),
    );

    // No live blur: a backdrop blur reads nothing inside a fade or the
    // overscroll stretch, so the glass went clear while a page moved and
    // flashed on every switch. The frost is a dense tint instead, the same
    // in every frame.
    Widget body = DecoratedBox(
      decoration: BoxDecoration(color: tint, borderRadius: shape),
      child: DecoratedBox(
        decoration: sheen,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (g != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: shape,
                      gradient: RadialGradient(
                        radius: 1.1,
                        colors: [
                          g.withValues(alpha: 0),
                          g.withValues(alpha: 0.30 * k),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // The brighter top edge of the rim.
            Positioned(
              left: radius * 0.6,
              right: radius * 0.6,
              top: 0,
              height: 1.5,
              child: const IgnorePointer(child: ColoredBox(color: rimTop)),
            ),
            child,
          ],
        ),
      ),
    );
    body = ClipRRect(borderRadius: shape, child: body);
    return CustomPaint(
      painter: _OutsideShadows(
        radius: radius,
        shadows: [
          if (shadow)
            const BoxShadow(
              color: Color(0x59000000),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          if (g != null) ...[
            BoxShadow(color: g.withValues(alpha: 0.7 * k), spreadRadius: 1.5),
            BoxShadow(color: g.withValues(alpha: 0.55 * k), blurRadius: 24),
          ],
        ],
      ),
      child: DecoratedBox(
        decoration: border,
        position: DecorationPosition.foreground,
        child: body,
      ),
    );
  }
}

/// Shadows drawn only outside the rounded box, as CSS draws them: under a
/// see-through panel a shadow painted beneath it would darken (or, for a
/// glow, colour) the glass itself.
class _OutsideShadows extends CustomPainter {
  _OutsideShadows({required this.radius, required this.shadows});

  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(80)),
        Path()..addRRect(box),
      ),
    );
    for (final shadow in shadows) {
      final paint = shadow.toPaint();
      canvas.drawRRect(
        box.shift(shadow.offset).inflate(shadow.spreadRadius),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutsideShadows old) =>
      old.radius != radius || !listEquals(old.shadows, shadows);
}
