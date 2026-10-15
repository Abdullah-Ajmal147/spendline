import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/entry.dart';
import 'theme.dart';

/// App-wide messenger so toasts work from anywhere, even after a widget is gone.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Timer? _toastTimer;

/// Shows a short message. It always closes itself: Flutter keeps snackbars that have an action open
/// indefinitely when accessibility navigation is on, so the timer here does not depend on that.
void toast(String message, {VoidCallback? undo}) {
  final m = messengerKey.currentState;
  if (m == null) return;
  _toastTimer?.cancel();
  m.clearSnackBars();
  final seconds = undo == null ? 2 : 4;
  m.showSnackBar(SnackBar(
    content: Text(message),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
    duration: Duration(seconds: seconds),
    persist: false,
    showCloseIcon: false,
    dismissDirection: DismissDirection.horizontal,
    action: undo == null
        ? null
        : SnackBarAction(
            label: 'Undo',
            onPressed: () {
              _toastTimer?.cancel();
              undo();
            }),
  ));
  _toastTimer = Timer(Duration(seconds: seconds, milliseconds: 300), () {
    messengerKey.currentState?.hideCurrentSnackBar();
  });
}

/// Borderless text field look for inputs that sit inside glass.
InputDecoration bareInput({String? hint, TextStyle? hintStyle}) => InputDecoration(
      isCollapsed: true,
      hintText: hint,
      hintStyle: hintStyle,
      filled: false,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );

/// The liquid-glass material: blurred backdrop, translucent fill,
/// a bright top-left sheen and a hairline light edge.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.strong = false,
    this.blur = 26,
    this.shadow = true,
  });

  /// A cheap variant for long lists: no backdrop blur and no shadow, just the tinted surface.
  const Glass.flat({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.strong = false,
  })  : blur = 0,
        shadow = false;

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final double blur;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = BorderRadius.circular(radius);
    final surface = DecoratedBox(
            decoration: BoxDecoration(
              color: strong ? p.glassStrong : p.glass,
              borderRadius: r,
              border: Border.all(color: p.edge),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0, .38, .72, 1],
                  colors: [p.sheen, p.sheen.withValues(alpha: 0), p.lo.withValues(alpha: 0), p.lo],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow
            ? [BoxShadow(color: p.shadow, blurRadius: 32, spreadRadius: -12, offset: const Offset(0, 14))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: blur > 0 ? BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: surface) : surface,
      ),
    );
  }
}

/// Springy press feedback, like iOS liquid controls.
class Press extends StatefulWidget {
  const Press({super.key, required this.child, this.onTap, this.label});

  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .94 : 1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Slowly drifting color fields the glass panels refract.
class Aurora extends StatefulWidget {
  const Aurora({super.key});

  /// "Calm background": a still picture instead of the slow animation. Saves battery on cheap phones.
  static final ValueNotifier<bool> calm = ValueNotifier<bool>(false);

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 26));

  @override
  void initState() {
    super.initState();
    Aurora.calm.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    final still = MediaQuery.of(context).disableAnimations || Aurora.calm.value;
    if (still) {
      _c.stop();
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    Aurora.calm.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  Widget _blob(Color color, double size, double left, double top) => Positioned(
        left: left,
        top: top,
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: .78), color.withValues(alpha: 0)]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // Own layer: the moving background must not force the chat list to repaint with it.
    return RepaintBoundary(
      child: IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight, m = math.max(w, h);
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return Stack(children: [
              _blob(p.blobA, m * 1.0, -m * .38 + t * w * .14, -m * .42 + t * h * .08),
              _blob(p.blobB, m * .8, w - m * .45 - t * w * .16, h * .16 - t * h * .05),
              _blob(p.blobC, m * .75, -m * .2 + t * w * .2, h - m * .42 - t * h * .1),
            ]);
          },
        );
      }),
    ));
  }
}

IconData iconFor(Entry e) => _icon(e.type, e.category);

IconData _icon(EntryType type, String category) {
  switch (type) {
    case EntryType.given:
      return Icons.north_east_rounded;
    case EntryType.received:
      return Icons.south_west_rounded;
    case EntryType.income:
      return Icons.south_rounded;
    case EntryType.expense:
      break;
  }
  return switch (category) {
    'Food' => Icons.restaurant_rounded,
    'Transport' => Icons.directions_car_rounded,
    'Bills' => Icons.bolt_rounded,
    'Housing' => Icons.home_rounded,
    'Shopping' => Icons.shopping_bag_rounded,
    'Health' => Icons.medical_services_rounded,
    'Education' => Icons.menu_book_rounded,
    'Entertainment' => Icons.movie_rounded,
    'Charity' => Icons.volunteer_activism_rounded,
    'Personal' => Icons.face_retouching_natural_rounded,
    _ => Icons.more_horiz_rounded,
  };
}

/// Colored pill that shows the entry type; tap to cycle.
class TypePill extends StatelessWidget {
  const TypePill({super.key, required this.type, required this.onTap});

  final EntryType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.typeColor(type);
    return Press(
      onTap: onTap,
      label: '${type.verb}. Tap to change type',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: p.typeBg(type), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(type == EntryType.expense ? Icons.remove_rounded : _icon(type, 'Other'), size: 15, color: c),
          const SizedBox(width: 6),
          Text(type.verb, style: body(13, color: c, weight: FontWeight.w700)),
          const SizedBox(width: 4),
          Icon(Icons.unfold_more_rounded, size: 14, color: c.withValues(alpha: .7)),
        ]),
      ),
    );
  }
}
