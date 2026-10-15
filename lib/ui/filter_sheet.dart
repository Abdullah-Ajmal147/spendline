import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../models/filter.dart';
import '../services/parser.dart';
import '../state/app_state.dart';
import 'entry_editor.dart' show dayLabelFor;
import 'glass.dart';
import 'theme.dart';

Future<void> showFilterSheet(BuildContext context, AppState s) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (_) => _FilterSheet(state: s),
    );

enum _Range { any, today, week, month, lastMonth, custom }

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.state});
  final AppState state;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late EntryFilter f = widget.state.filter;
  late final _q = TextEditingController(text: f.query);
  _Range _range = _Range.any;

  @override
  void initState() {
    super.initState();
    if (f.from != null || f.to != null) _range = _Range.custom;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _setRange(_Range r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String? from;
    String? to;
    switch (r) {
      case _Range.any:
        break;
      case _Range.today:
        from = to = isoDate(today);
      case _Range.week:
        from = isoDate(today.subtract(const Duration(days: 6)));
        to = isoDate(today);
      case _Range.month:
        from = isoDate(DateTime(now.year, now.month, 1));
        to = isoDate(today);
      case _Range.lastMonth:
        from = isoDate(DateTime(now.year, now.month - 1, 1));
        to = isoDate(DateTime(now.year, now.month, 0));
      case _Range.custom:
        return;
    }
    setState(() {
      _range = r;
      f = f.copyWith(from: from, to: to);
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: f.from != null && f.to != null
          ? DateTimeRange(start: DateTime.parse(f.from!), end: DateTime.parse(f.to!))
          : null,
    );
    if (r == null) return;
    setState(() {
      _range = _Range.custom;
      f = f.copyWith(from: isoDate(r.start), to: isoDate(r.end));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = widget.state;
    final matches = s.entries.where(f.copyWith(query: _q.text).matches).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Glass(
              strong: true,
              radius: 30,
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Search & filter', style: display(22, color: p.ink)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'Search name, item, note or amount', prefixIcon: Icon(Icons.search_rounded)),
                  ),
                  const SizedBox(height: 14),
                  Text('TYPE', style: eyebrow(p.ink3, size: 10.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final t in EntryType.values)
                      FilterChip(
                        label: Text(t.label),
                        selected: f.types.contains(t),
                        onSelected: (on) => setState(() {
                          final next = {...f.types};
                          on ? next.add(t) : next.remove(t);
                          f = f.copyWith(types: next);
                        }),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  Text('WHEN', style: eyebrow(p.ink3, size: 10.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in const {
                      _Range.any: 'Any time',
                      _Range.today: 'Today',
                      _Range.week: 'Last 7 days',
                      _Range.month: 'This month',
                      _Range.lastMonth: 'Last month',
                    }.entries)
                      ChoiceChip(label: Text(e.value), selected: _range == e.key, onSelected: (_) => _setRange(e.key)),
                    ChoiceChip(
                      label: Text(_range == _Range.custom && f.from != null
                          ? '${dayLabelFor(f.from!)} – ${dayLabelFor(f.to ?? f.from!)}'
                          : 'Pick dates'),
                      selected: _range == _Range.custom,
                      onSelected: (_) => _pickRange(),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _menu(p, 'CATEGORY', f.category, s.categoriesInUse, (v) => setState(() => f = f.copyWith(category: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _menu(p, 'PERSON', f.person, s.peopleInUse, (v) => setState(() => f = f.copyWith(person: v)))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          s.setFilter(EntryFilter.none);
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          s.setFilter(f.copyWith(query: _q.text));
                          Navigator.pop(context);
                        },
                        child: Text('Show $matches ${matches == 1 ? 'entry' : 'entries'}'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(Palette p, String label, String? value, List<String> options, ValueChanged<String?> onPick) {
    return PopupMenuButton<String?>(
      onSelected: onPick,
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('Any')),
        for (final o in options) PopupMenuItem(value: o, child: Text(o)),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: eyebrow(p.ink3, size: 10.5)),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(child: Text(value ?? 'Any', style: body(15, color: p.ink, weight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            Icon(Icons.expand_more_rounded, size: 18, color: p.ink3),
          ]),
        ]),
      ),
    );
  }
}
