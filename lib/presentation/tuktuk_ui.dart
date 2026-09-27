part of '../main.dart';

class TuktukTheme {
  static const background = Color(0xFF050B10);
  static const backgroundSoft = Color(0xFF09141C);
  static const surface = Color(0xEC141D24);
  static const surfaceStrong = Color(0xF6172028);
  static const surfaceSoft = Color(0xE51A252D);
  static const border = Color(0xFF3A4853);
  static const mint = Color(0xFF35D6A2);
  static const mintSoft = Color(0xFF6FE6BD);
  static const gold = Color(0xFFE5A84E);
  static const goldSurface = Color(0xFFDCA24C);
  static const goldDark = gold;
  static const text = Color(0xFFF6F8FA);
  static const muted = Color(0xFFAAB6C5);
  static const danger = Color(0xFFFF5E59);

  static const inputDecoration = InputDecorationTheme(
    filled: true,
    fillColor: surfaceSoft,
    hintStyle: TextStyle(color: muted, fontSize: 17),
    labelStyle: TextStyle(color: muted),
    prefixIconColor: mint,
    suffixIconColor: muted,
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 19),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide(color: mint, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide(color: danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide(color: danger, width: 1.6),
    ),
  );
}

class TuktukFlowHeader extends StatelessWidget {
  const TuktukFlowHeader({
    required this.step,
    this.onBack,
    super.key,
  });

  final int step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final horizontalPadding = compact ? 16.0 : 24.0;
          final stepWidth = compact ? 70.0 : 82.0;
          final gap = compact ? 6.0 : 8.0;
          final availableBrandWidth =
              constraints.maxWidth - (horizontalPadding * 2) - stepWidth - gap;
          final brandWidth = availableBrandWidth.clamp(
            compact ? 101.52 : 113.4,
            137.7,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              10,
              horizontalPadding,
              8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: brandWidth,
                  child: _TuktukBrandLockup(width: brandWidth),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Paso $step de 6',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: compact ? 11.5 : 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TuktukProgressIndicator(step: step),
                      const SizedBox(height: 3),
                      Visibility(
                        visible: onBack != null,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: SizedBox(
                          height: compact ? 34 : 36,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: onBack,
                              style: TextButton.styleFrom(
                                foregroundColor: TuktukTheme.mint,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                Icons.arrow_back_rounded,
                                size: compact ? 18 : 20,
                              ),
                              label: Text(
                                'Volver',
                                style: TextStyle(
                                  fontSize: compact ? 14 : 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class TuktukProgressIndicator extends StatelessWidget {
  const TuktukProgressIndicator({required this.step, super.key});
  final int step;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final indicatorWidth = compact ? 94.0 : 112.0;

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: indicatorWidth,
        child: Row(
          children: List.generate(
            6,
            (i) => Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 4,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                decoration: BoxDecoration(
                  color: i < step ? TuktukTheme.mint : TuktukTheme.border,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TuktukPrimaryButton extends StatelessWidget {
  const TuktukPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      opacity: enabled ? 1 : .45,
      duration: const Duration(milliseconds: 150),
      child: SizedBox(
        height: 64,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [TuktukTheme.goldSurface, TuktukTheme.goldSurface],
            ),
            borderRadius: BorderRadius.all(Radius.circular(34)),
            boxShadow: [
              BoxShadow(
                color: Color(0x55E5A84E),
                blurRadius: 22,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(34),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(icon, color: Colors.white, size: 27),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TuktukGlassCard extends StatelessWidget {
  const TuktukGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
    this.radius = 24,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF018222A), Color(0xE7121A20)],
          ),
          border: Border.all(color: borderColor ?? TuktukTheme.border),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: child,
      );
}

class TuktukSectionSheet extends StatelessWidget {
  const TuktukSectionSheet({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFA121B21), Color(0xFF081116)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: TuktukTheme.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 26,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: child,
      );
}

class TuktukMapButton extends StatelessWidget {
  const TuktukMapButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? const Color(0xE0233B38) : const Color(0xE70D151A),
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? TuktukTheme.mint : TuktukTheme.border,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: TuktukTheme.mint, size: 22),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TuktukTheme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class TuktukActionChip extends StatelessWidget {
  const TuktukActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 108;
          return Material(
            color: active ? const Color(0xE0263C39) : const Color(0xD9152026),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 7 : 11,
                  vertical: compact ? 7 : 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? TuktukTheme.mint : TuktukTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: compact
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 21,
                            color: active
                                ? TuktukTheme.mint
                                : TuktukTheme.mintSoft,
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: active
                                ? TuktukTheme.mint
                                : TuktukTheme.mintSoft,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      );
}

class TuktukServiceCard extends StatelessWidget {
  const TuktukServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0x33E5A84E), Color(0x1FE5A84E)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xE718222A), Color(0xE510181E)],
                      ),
                border: Border.all(
                  color: selected ? TuktukTheme.gold : TuktukTheme.border,
                  width: selected ? 1.6 : 1,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? TuktukTheme.gold : TuktukTheme.muted,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    icon,
                    color: selected ? Colors.white : TuktukTheme.muted,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: TuktukTheme.muted,
                            fontSize: 12.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    price,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : TuktukTheme.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class TuktukSummaryRow extends StatelessWidget {
  const TuktukSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = TuktukTheme.mint,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 23),
            const SizedBox(width: 15),
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: const TextStyle(
                  color: TuktukTheme.muted,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: TuktukTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class TuktukMetricPill extends StatelessWidget {
  const TuktukMetricPill({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xE80B1419),
          border: Border.all(color: TuktukTheme.border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: TuktukTheme.mint, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
}

class TuktukBrandHeader extends StatelessWidget {
  const TuktukBrandHeader({
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 6, 18, 5),
    super.key,
  });

  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final trailingSpace = trailing == null ? 0.0 : 56.0;
          final width =
              (constraints.maxWidth - padding.horizontal - trailingSpace)
                  .clamp(108.0, 137.7);

          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TuktukBrandLockup(width: width),
                const Spacer(),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
          );
        },
      );
}

class _TuktukBrandLockup extends StatelessWidget {
  const _TuktukBrandLockup({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'TUKTUK - Tu ciudad te mueve',
        image: true,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: width,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    maxLines: 1,
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 66,
                        height: .92,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3.4,
                      ),
                      children: [
                        TextSpan(
                          text: 'TUK',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'TUK',
                          style: TextStyle(color: TuktukTheme.gold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                width: width,
                child: const FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'T U   C I U D A D   T E   M U E V E',
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(0xFFD0D6DC),
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class TuktukMapLoadingOverlay extends StatefulWidget {
  const TuktukMapLoadingOverlay({super.key});

  @override
  State<TuktukMapLoadingOverlay> createState() =>
      _TuktukMapLoadingOverlayState();
}

class _TuktukMapLoadingOverlayState extends State<TuktukMapLoadingOverlay> {
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xF2081218),
            ),
            child: Center(
              child: TuktukGlassCard(
                padding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: TuktukTheme.mint,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Cargando mapa…',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: TuktukTheme.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class TuktukStatusOrb extends StatefulWidget {
  const TuktukStatusOrb({
    required this.icon,
    this.active = true,
    super.key,
  });

  final IconData icon;
  final bool active;

  @override
  State<TuktukStatusOrb> createState() => _TuktukStatusOrbState();
}

class _TuktukStatusOrbState extends State<TuktukStatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant TuktukStatusOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;

    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? TuktukTheme.mint : TuktukTheme.gold;

    return SizedBox(
      width: 116,
      height: 116,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phase = widget.active ? _controller.value : 0.0;
          final breathe =
              widget.active ? .92 + ((sin(phase * pi * 2) + 1) * .055) : 1.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                for (var index = 0; index < 3; index++)
                  _TuktukRadarPulse(
                    color: color,
                    phase: (phase + (index / 3)).remainder(1.0),
                  ),
              Transform.scale(
                scale: breathe,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: .18),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(
                          alpha: widget.active ? .34 : .18,
                        ),
                        blurRadius: widget.active ? 30 : 18,
                        spreadRadius: widget.active ? 4 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: 31,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TuktukRadarPulse extends StatelessWidget {
  const _TuktukRadarPulse({
    required this.color,
    required this.phase,
  });

  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final size = 64 + (50 * phase);
    final opacity = (1 - phase) * .52;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.5,
        ),
      ),
    );
  }
}

class TuktukHavanaBackdrop extends StatelessWidget {
  const TuktukHavanaBackdrop({
    required this.child,
    this.showLighthouse = false,
    this.showRelief = false,
    super.key,
  });
  final Widget child;
  final bool showLighthouse;
  final bool showRelief;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    TuktukTheme.background,
                    Color(0xFF07141B),
                    Color(0xFF0A2228),
                  ],
                ),
              ),
            ),
          ),
          if (showRelief)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: .48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: .42,
                          child: Image.asset(
                            'assets/branding/tuktuk_havana_shadow_relief.jpg',
                            fit: BoxFit.cover,
                            alignment: Alignment.bottomCenter,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                TuktukTheme.background,
                                Color(0xD9081218),
                                Color(0x66081218),
                                Color(0x14081218),
                              ],
                              stops: [0, .22, .56, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      );
}
