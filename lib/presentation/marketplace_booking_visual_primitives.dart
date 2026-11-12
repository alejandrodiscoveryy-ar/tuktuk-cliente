part of '../main.dart';

// Cristal marino y veta acuática: fondo opaco para que el mapa no compita
// con las etiquetas; iluminación dorada únicamente cuando está seleccionado.
class _MarineCardSurface extends StatelessWidget {
  const _MarineCardSurface({
    required this.selected,
    required this.child,
    required this.padding,
    this.radius = 16,
    this.tint,
  });

  final bool selected;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.8, -.85),
            radius: 1.7,
            colors: tint == null
                ? (selected
                    ? const [
                        Color(0xF28B6A39),
                        Color(0xF0263C46),
                        Color(0xF5091724)
                      ]
                    : const [
                        Color(0xF23A5D65),
                        Color(0xF01A303C),
                        Color(0xF5081722)
                      ])
                : <Color>[
                    Color.lerp(const Color(0xFF17333E), tint,
                            selected ? .52 : .28)!
                        .withValues(alpha: .94),
                    Color.lerp(const Color(0xFF0D2230), tint,
                            selected ? .19 : .10)!
                        .withValues(alpha: .94),
                    const Color(0xF5081722),
                  ],
            stops: const [0, .48, 1],
          ),
          border: Border.all(
            color: tint == null
                ? (selected ? TuktukTheme.gold : const Color(0xB56A9EA6))
                : tint!.withValues(alpha: selected ? .95 : .55),
            width: selected ? 1.8 : 1,
          ),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: tint == null
                  ? (selected ? const Color(0x66E5A84E) : const Color(0x55000000))
                  : tint!.withValues(alpha: selected ? .30 : .08),
              blurRadius: selected ? 16 : 9,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            painter: const _MarineVeinsPainter(),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

class _MarineVeinsPainter extends CustomPainter {
  const _MarineVeinsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final trace = Paint()
      ..color = const Color(0x2A98F3DD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final highlight = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    // Trazos Bezier discretizados para evitar el Path<LatLng> de flutter_map.
    _drawMarineCubic(
      canvas,
      trace,
      Offset(-w * .10, h * .34),
      Offset(w * .24, -h * .12),
      Offset(w * .44, h * .93),
      Offset(w * 1.1, h * .22),
    );
    _drawMarineCubic(
      canvas,
      highlight,
      Offset(-w * .06, h * .76),
      Offset(w * .28, h * .13),
      Offset(w * .70, h * 1.20),
      Offset(w * 1.08, h * .55),
    );
  }

  // Curva cubica suave dibujada solo con Offset y Canvas de Flutter.
  static void _drawMarineCubic(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset control1,
    Offset control2,
    Offset end,
  ) {
    var previous = start;
    for (var i = 1; i <= 32; i++) {
      final t = i / 32.0;
      final u = 1.0 - t;
      final u3 = u * u * u;
      final t3 = t * t * t;
      final a = 3 * u * u * t;
      final b = 3 * u * t * t;
      final next = Offset(
        u3 * start.dx + a * control1.dx + b * control2.dx + t3 * end.dx,
        u3 * start.dy + a * control1.dy + b * control2.dy + t3 * end.dy,
      );
      canvas.drawLine(previous, next, paint);
      previous = next;
    }
  }

  @override
  bool shouldRepaint(covariant _MarineVeinsPainter oldDelegate) => false;
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard(this.icon, this.title, this.detail);

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: TuktukTheme.mint.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: TuktukTheme.mint, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TuktukTheme.muted,
                      fontSize: 13.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MiniFact extends StatelessWidget {
  const _MiniFact(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: TuktukTheme.mint, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

