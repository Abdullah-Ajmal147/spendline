import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import 'glass.dart';
import 'theme.dart';

/// Three short pages shown once: what it does, how to talk to it, what you get.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.state, required this.onDone});
  final AppState state;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;
  static const _currencies = ['Rs', 'PKR', '₹', r'$', 'AED', '£', '€'];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await widget.state.completeOnboarding();
    widget.onDone();
  }

  void _next() {
    if (_i == 2) {
      _finish();
    } else {
      _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: TextButton(onPressed: _finish, child: Text('Skip', style: body(14, color: p.ink2))),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    onPageChanged: (v) => setState(() => _i = v),
                    children: [_pageSay(p), _pageLanguages(p), _pageMore(p)],
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var d = 0; d < 3; d++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: d == _i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: d == _i ? p.accent : p.ink3.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: FilledButton(onPressed: _next, child: Text(_i == 2 ? 'Get started' : 'Next')),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _frame(Palette p, {required String title, required String body_, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        child,
        const SizedBox(height: 30),
        Text(title, style: display(32, color: p.ink)),
        const SizedBox(height: 10),
        Text(body_, style: body(16, color: p.ink2, height: 1.45)),
        const Spacer(),
      ]),
    );
  }

  Widget _bubble(Palette p, String t) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(t, style: body(16, color: p.accentInk)),
        ),
      );

  Widget _card(Palette p, IconData icon, Color c, Color bg, String title, String sub) => Align(
        alignment: Alignment.centerLeft,
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, size: 21, color: c),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(15, color: p.ink, weight: FontWeight.w700)),
              Text(sub, style: body(12.5, color: p.ink3)),
            ]),
          ]),
        ),
      );

  Widget _pageSay(Palette p) => _frame(
        p,
        title: 'Just say it',
        body_: 'No forms, no categories to pick. Type what happened, like a message, and Spendline files it.',
        child: Column(children: [
          _bubble(p, 'lunch 500, chai 120'),
          const SizedBox(height: 8),
          _card(p, Icons.restaurant_rounded, p.spent, p.spentBg, 'Spent Rs 500 · Lunch', 'Food'),
          const SizedBox(height: 6),
          _card(p, Icons.restaurant_rounded, p.spent, p.spentBg, 'Spent Rs 120 · Chai', 'Food'),
        ]),
      );

  Widget _pageLanguages(Palette p) => _frame(
        p,
        title: 'Roman Urdu is fine',
        body_: 'Write it the way you talk, or tap the mic and speak. It understands kal, diye, liye, hazaar and more.',
        child: Column(children: [
          _bubble(p, 'mainy 500 rizwan ko dy ha'),
          const SizedBox(height: 8),
          _card(p, Icons.north_east_rounded, p.lent, p.lentBg, 'Gave Rs 500 to Rizwan', 'Lending'),
          const SizedBox(height: 14),
          _bubble(p, 'ali se 1000 liye'),
          const SizedBox(height: 8),
          _card(p, Icons.south_west_rounded, p.recv, p.recvBg, 'Got Rs 1,000 from Ali', 'Lending'),
        ]),
      );

  Widget _pageMore(Palette p) {
    final s = widget.state;
    return _frame(
      p,
      title: 'Yours, and everywhere',
      body_: 'Split trips with friends, see who owes you, and keep a backup in your own Google account.',
      child: Glass(
        radius: 26,
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOUR CURRENCY', style: eyebrow(p.ink3, size: 11)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _currencies)
                ChoiceChip(
                  label: Text(c),
                  selected: s.currency == c,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    s.setCurrency(c);
                  },
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
