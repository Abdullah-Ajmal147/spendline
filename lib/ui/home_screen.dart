import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import 'entry_editor.dart';
import 'glass.dart';
import 'person_screen.dart';
import 'theme.dart';

String dayLabel(String iso) => dayLabelFor(iso);

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          bottom: false,
          child: ListenableBuilder(listenable: s, builder: (context, _) => _content(context, p)),
        ),
      ]),
    );
  }

  Widget _content(BuildContext context, Palette p) {
    final people = s.people;
    return LayoutBuilder(builder: (context, box) {
      final side = math.max(16.0, (box.maxWidth - 520) / 2);
      return RefreshIndicator(
        onRefresh: s.sync,
        color: p.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(side, 10, side, 40),
          children: [
            _header(context, p),
            const SizedBox(height: 18),
            if (s.notice != null) ...[
              Glass(
                radius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.notice!, style: body(13, color: p.ink2))),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            HeroCard(state: s),
            const SizedBox(height: 22),
            if (people.isNotEmpty) ...[
              _sectionTitle(p, 'People', 'Tap a name for the full ledger'),
              const SizedBox(height: 8),
              PeopleStrip(state: s, people: people),
              const SizedBox(height: 18),
            ],
            _sectionTitle(p, 'Recent', s.entries.isEmpty ? '' : 'Swipe left to delete'),
            const SizedBox(height: 8),
            RecentList(state: s),
          ],
        ),
      );
    });
  }

  Widget _header(BuildContext context, Palette p) {
    return Row(children: [
      Press(
        onTap: () => Navigator.pop(context),
        label: 'Back to chat',
        child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
      ),
      const SizedBox(width: 12),
      Text('Summary', style: display(22, color: p.ink)),
    ]);
  }

  Widget _sectionTitle(Palette p, String title, String aside) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, style: display(18, color: p.ink)),
          const Spacer(),
          Text(aside, style: body(12.5, color: p.ink3)),
        ]),
      );
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = state;
    final month = DateFormat('MMMM').format(DateTime.now()).toUpperCase();
    final days = s.lastDays(14);
    final maxV = days.fold<double>(1, (a, b) => math.max(a, b));

    return Glass(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SPENT IN $month', style: eyebrow(p.ink2)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s.currency, style: body(17, color: p.ink2, weight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(s.fmt(s.spentThisMonth), style: display(50, color: p.ink)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Semantics(
          label: 'Daily spending for the last 14 days',
          child: SizedBox(
            height: 46,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      height: days[i] > 0 ? math.max(7.0, days[i] / maxV * 46) : 4.0,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(2)),
                        color: days[i] > 0 ? null : p.lo,
                        gradient: days[i] > 0
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [p.accent, p.accent.withValues(alpha: .35)],
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('14 days ago', style: body(11, color: p.ink3)),
          const Spacer(),
          Text('Today', style: body(11, color: p.ink3)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat(value: s.fmt(s.spentToday), label: 'Spent today', color: p.ink)),
          const SizedBox(width: 8),
          Expanded(child: _Stat(value: s.fmt(s.owedToYou), label: 'Others owe you', color: p.lent)),
          const SizedBox(width: 8),
          Expanded(child: _Stat(value: s.fmt(s.moneyInThisMonth), label: 'Money in', color: p.recv)),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: display(16, color: color)),
        ),
        const SizedBox(height: 3),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11.5, color: p.ink2)),
      ]),
    );
  }
}

class PeopleStrip extends StatelessWidget {
  const PeopleStrip({super.key, required this.state, required this.people});
  final AppState state;
  final List<PersonBalance> people;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final x = people[i];
          final fg = x.balance > 0 ? p.lent : x.balance < 0 ? p.recv : p.ink3;
          final bg = x.balance > 0 ? p.lentBg : x.balance < 0 ? p.recvBg : p.lo;
          final line = x.balance > 0
              ? 'owes you ${state.money(x.balance)}'
              : x.balance < 0
                  ? 'you owe ${state.money(-x.balance)}'
                  : 'settled';
          return Press(
           onTap: () => Navigator.push(
              context, MaterialPageRoute<void>(builder: (_) => PersonScreen(state: state, name: x.name))),
           label: 'Open ${x.name}',
           child: Glass(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: bg,
                child: Text(x.name.isEmpty ? '?' : x.name[0], style: display(15, color: fg)),
              ),
              const SizedBox(width: 10),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.name, style: body(14, color: p.ink, weight: FontWeight.w600)),
                Text(line, style: body(12, color: p.ink2)),
              ]),
            ]),
          ));
        },
      ),
    );
  }
}

class RecentList extends StatelessWidget {
  const RecentList({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = state;

    if (s.entries.isEmpty) {
      return Glass(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(children: [
          Text('Nothing logged yet',
              textAlign: TextAlign.center, style: display(17, color: p.ink)),
          const SizedBox(height: 6),
          Text('Go back and type something like "pay for lunch 500".',
              textAlign: TextAlign.center, style: body(14, color: p.ink2)),
        ]),
      );
    }

    final rows = <Widget>[];
    var last = '';
    for (final e in s.entries.take(120)) {
      if (e.date != last) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(dayLabel(e.date).toUpperCase(), style: eyebrow(p.ink3)),
        ));
        last = e.date;
      }
      rows.add(EntryRow(entry: e, state: s));
    }
    return Glass(
      radius: 26,
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry, required this.state});
  final Entry entry;
  final AppState state;

  Future<void> _delete() async {
    await state.remove(entry);
    toast('Deleted', undo: () => state.restore(entry));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = entry;
    final sign = switch (e.type) {
      EntryType.expense => '−',
      EntryType.given => '→ ',
      _ => '+',
    };
    final sub = [
      e.category,
      if (e.type != EntryType.expense) e.type.label,
      if (e.time.isNotEmpty) e.time,
      if (state.connected && e.pending) 'Waiting to sync',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: p.spentBg, borderRadius: BorderRadius.circular(18)),
        child: Icon(Icons.delete_outline_rounded, color: p.spent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.typeBg(e.type), borderRadius: BorderRadius.circular(14)),
            child: Icon(iconFor(e), size: 20, color: p.typeColor(e.type)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.description.isEmpty ? e.category : e.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: body(15, color: p.ink, weight: FontWeight.w600)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: p.ink3)),
            ]),
          ),
          const SizedBox(width: 8),
          Text('$sign${state.money(e.amount)}',
              style: display(15.5, color: e.type == EntryType.expense ? p.ink : p.typeColor(e.type), weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
