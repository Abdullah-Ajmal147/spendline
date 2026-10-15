import 'package:flutter/material.dart';

import 'theme.dart';

/// Continues the native splash (same colour, same bars) with a short rise animation.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _heights = [0.42, 0.66, 1.0];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0B2B26) : const Color(0xFF0F8F7C);
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            double bar(int i) {
              final t = ((_c.value - i * 0.12) / 0.5).clamp(0.0, 1.0);
              return Curves.easeOutBack.transform(t);
            }

            final text = Curves.easeOut.transform(((_c.value - 0.45) / 0.4).clamp(0.0, 1.0));
            return Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 120,
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Container(
                      width: 24,
                      height: 120 * _heights[i] * bar(i).clamp(0.0, 1.15),
                      decoration: BoxDecoration(
                        color: i == 2 ? const Color(0xFFFFD166) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 26),
              Opacity(
                opacity: text,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - text)),
                  child: Column(children: [
                    Text('Spendline', style: display(34, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Say it. It is logged.', style: body(15, color: Colors.white.withValues(alpha: .8))),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
