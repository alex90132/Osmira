import 'package:flutter/material.dart';

/// Softly dissolves the top and/or bottom edge of a scrollable child into the
/// background instead of hard-clipping it. The scrolling content appears to
/// melt away as it slides under a header (top) or over the bottom action bar
/// (bottom) — the same treatment used on the app-routing screen.
///
/// Implemented with a [ShaderMask] in [BlendMode.dstIn], so only the child's
/// alpha is touched (the gradient colour is irrelevant — just its opacity).
/// The fade bands are a fixed pixel height, converted to gradient stop
/// fractions against the laid-out height so they stay visually constant
/// regardless of the viewport size.
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.child,
    this.top = 28.0,
    this.bottom = 28.0,
  });

  final Widget child;

  /// Height of the top fade band in logical pixels (0 disables it).
  final double top;

  /// Height of the bottom fade band in logical pixels (0 disables it).
  final double bottom;

  @override
  Widget build(BuildContext context) {
    if (top <= 0 && bottom <= 0) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        if (!h.isFinite || h <= 0) return child;

        // Clamp so the two bands can never meet/overlap in a short viewport.
        final topFrac = (top / h).clamp(0.0, 0.5);
        final bottomFrac = (bottom / h).clamp(0.0, 0.5);

        final stops = <double>[0.0, topFrac, 1.0 - bottomFrac, 1.0];
        final colors = <Color>[
          top > 0 ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          bottom > 0 ? Colors.transparent : Colors.black,
        ];

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: stops,
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
