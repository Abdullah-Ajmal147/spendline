import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../models/filter.dart';
import '../services/parser.dart';
import '../services/voice.dart';
import '../state/app_state.dart';
import 'entry_editor.dart';
import 'filter_sheet.dart';
import 'glass.dart';
import 'groups_screen.dart';
import 'home_screen.dart';
import 'settings_sheet.dart';
import 'theme.dart';

const _examples = [
  'mainy 500 rizwan ko dy ha',
  'Pay for lunch 500',
  'ali se 1000 liye',
  'Uber 350 yesterday',
  'lunch 500, chai 120',
];

/// Main screen: type a sentence, the app answers with what it saved.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String? _reply; // transient assistant message, e.g. "no amount found"
  bool _busy = false;
  bool _listening = false;
  final _voice = Voice();

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _voice.stop();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _reply = null;
    });
    final err = await _voice.start(
      locale: s.voiceLocale,
      onText: (t, _) {
        if (!mounted) return;
        _text.text = t;
        _text.selection = TextSelection.collapsed(offset: t.length);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (err != null && mounted) {
      setState(() {
        _listening = false;
        _reply = err;
      });
    }
  }

  @override
  void dispose() {
    _voice.stop();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) s.sync();
  }

  Future<void> _send() async {
    final raw = _text.text.trim();
    if (raw.isEmpty || _busy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _reply = null;
    });
    _text.clear();
    // The list is reversed, so offset 0 is the newest message.
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
    try {
      var drafts = parseMany(raw);

      // Hard sentence and the optional on-device model is loaded: let it have a go.
      if (drafts.length == 1 && drafts.first.confidence < .8 && s.smart.ready) {
        try {
          final r = await s.smart.parse(raw, drafts.first);
          if (r != null) drafts = [r];
        } catch (_) {
          // Keep the rule-based guess.
        }
      }

      if (drafts.any((d) => d.amount <= 0)) {
        _text.text = raw;
        setState(() => _reply = 'I could not find an amount in that. Try something like "lunch 500" or "gave ali 2k".');
        return;
      }

      for (final d in drafts) {
        var draft = d;
        if (d.confidence < .8) {
          if (!mounted) return;
          final fixed = await showEntryEditor(
            context,
            s,
            d,
            title: 'Check this one',
            hint: '"$raw"',
            action: 'Save',
          );
          if (fixed == null) continue;
          await s.learn(d, fixed);
          draft = fixed;
        }
        await s.add(draft, raw);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus(); // keep the keyboard open between messages
      }
    }
  }

  Future<void> _edit(Entry e) async {
    final d = Draft(
      type: e.type,
      amount: e.amount,
      person: e.person,
      category: e.category,
      description: e.description,
      date: e.date,
      confidence: 1,
    );
    final r = await showEntryEditor(context, s, d, title: 'Edit entry', action: 'Update');
    if (r == null) return;
    await s.learn(d, r);
    await s.update(
      e,
      e.copyWith(
        type: r.type,
        amount: r.amount,
        person: r.person,
        category: r.category,
        description: r.description.trim().isEmpty ? r.category : r.description.trim(),
        date: r.date,
      ),
    );
  }

  Future<void> _delete(Entry e) async {
    HapticFeedback.mediumImpact();
    await s.remove(e);
    toast('Deleted', undo: () => s.restore(e));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          child: Column(children: [
            _header(p),
            _filterBar(p),
            Expanded(child: ListenableBuilder(listenable: s, builder: (context, _) => _thread(p))),
            _quickChips(p),
            _composer(p),
          ]),
        ),
      ]),
    );
  }

  Widget _header(Palette p) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: SweepGradient(colors: [p.blobA, p.blobC, p.blobB, p.blobA]),
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 420) ...[
                const SizedBox(width: 8),
                Text('Spendline', maxLines: 1, softWrap: false, style: display(20, color: p.ink)),
              ],
              Expanded(
                  child: Align(
                alignment: Alignment.centerRight,
                child: Press(
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SummaryScreen(state: s))),
                label: 'Summary',
                child: Glass(
                  radius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.insights_rounded, size: 18, color: p.ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${s.currency} ${s.compact(s.spentThisMonth)}',
                            maxLines: 1, style: body(13, color: p.ink, weight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ))),
              const SizedBox(width: 8),
              Press(
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupsScreen(state: s))),
                label: 'Groups',
                child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.groups_rounded, size: 20, color: p.ink)),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: () => showSettings(context, s),
                label: 'Settings',
                child: Glass(
                  radius: 999,
                  padding: const EdgeInsets.all(9),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Icon(Icons.tune_rounded, size: 20, color: p.ink),
                    if (s.connected)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.syncing || s.pendingCount > 0 ? p.lent : p.recv,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _filterBar(Palette p) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final f = s.filter;
        final shown = s.visibleEntries;
        double sum(EntryType t) => shown.where((e) => e.type == t).fold(0.0, (a, e) => a + e.amount);
        final now = DateTime.now();
        final monthStart = isoDate(DateTime(now.year, now.month, 1));
        final thisMonth = f.from == monthStart;
        final advanced = f.category != null || f.person != null || (f.from != null && !thisMonth) || f.to != null && !thisMonth;

        Widget chip(String label, bool on, VoidCallback tap, {IconData? icon}) => Press(
              onTap: () {
                HapticFeedback.selectionClick();
                tap();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: on ? p.accent : p.field,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: on ? p.accentInk : p.ink2), const SizedBox(width: 5)],
                  Text(label, style: body(13, color: on ? p.accentInk : p.ink2, weight: FontWeight.w600)),
                ]),
              ),
            );

        void toggleType(EntryType t) {
          final next = {...f.types};
          next.contains(t) ? next.remove(t) : next.add(t);
          s.setFilter(f.copyWith(types: next));
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                Glass.flat(
                  radius: 999,
                  padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 20, color: p.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => s.setFilter(f.copyWith(query: v)),
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        cursorColor: p.accent,
                        style: body(15, color: p.ink),
                        decoration: bareInput(hint: 'Search name, item or amount', hintStyle: body(15, color: p.ink3)),
                      ),
                    ),
                    if (f.query.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _search.clear();
                          s.setFilter(f.copyWith(query: ''));
                        },
                        icon: Icon(Icons.close_rounded, size: 18, color: p.ink2),
                      ),
                    IconButton(
                      tooltip: 'More filters',
                      onPressed: () => showFilterSheet(context, s),
                      icon: Badge(
                        isLabelVisible: advanced,
                        smallSize: 8,
                        child: Icon(Icons.tune_rounded, size: 20, color: advanced ? p.accent : p.ink2),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    chip('All', !f.active, () {
                      _search.clear();
                      s.setFilter(EntryFilter.none);
                    }),
                    const SizedBox(width: 6),
                    chip('Spent', f.types.contains(EntryType.expense), () => toggleType(EntryType.expense)),
                    const SizedBox(width: 6),
                    chip('Gave', f.types.contains(EntryType.given), () => toggleType(EntryType.given)),
                    const SizedBox(width: 6),
                    chip('Got', f.types.contains(EntryType.received), () => toggleType(EntryType.received)),
                    const SizedBox(width: 6),
                    chip('This month', thisMonth, () {
                      thisMonth
                          ? s.setFilter(f.copyWith(from: null, to: null))
                          : s.setFilter(f.copyWith(from: monthStart, to: isoDate(DateTime(now.year, now.month + 1, 0))));
                    }, icon: Icons.calendar_month_rounded),
                  ]),
                ),
                if (f.active)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          '${shown.length} ${shown.length == 1 ? 'entry' : 'entries'}',
                          if (sum(EntryType.expense) > 0) 'spent ${s.money(sum(EntryType.expense))}',
                          if (sum(EntryType.given) > 0) 'gave ${s.money(sum(EntryType.given))}',
                          if (sum(EntryType.received) + sum(EntryType.income) > 0)
                            'in ${s.money(sum(EntryType.received) + sum(EntryType.income))}',
                        ].join(' · '),
                        style: body(12.5, color: p.ink2),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _thread(Palette p) {
    final list = s.visibleEntries; // newest first, and the list is reversed so newest sits at the bottom

    // Lightweight row descriptors: widgets are only built for rows that are on screen.
    final rows = <Object>[];
    if (_reply != null) rows.add(_assistantBubble(p, _reply!));
    if (s.showBackupNudge) rows.add(_nudge(p));
    if (s.notice != null) rows.add(_notice(p, s.notice!));
    for (var i = 0; i < list.length; i++) {
      rows.add(list[i]);
      final older = i + 1 < list.length ? list[i + 1] : null;
      if (older == null || older.date != list[i].date) rows.add(list[i].date);
    }
    if (list.isEmpty && s.filter.active) {
      rows.add(_assistantBubble(p, 'Nothing matches this filter. Clear it to see everything.'));
    } else if (list.isEmpty) {
      rows.add(_welcome(p));
    }
    final newestId = list.isEmpty ? null : list.first.id;

    return LayoutBuilder(builder: (context, box) {
      final side = math.max(14.0, (box.maxWidth - 520) / 2);
      return ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: EdgeInsets.fromLTRB(side, 8, side, 12),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          if (r is Widget) return r;
          if (r is String) return _dayChip(p, r);
          final e = r as Entry;
          final card = _EntryMessage(key: ValueKey(e.id), entry: e, state: s, onEdit: _edit, onDelete: _delete);
          if (e.id != newestId) return card;
          // Only the newest message animates in; older ones appear instantly while scrolling.
          return TweenAnimationBuilder<double>(
            key: ValueKey('anim-${e.id}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
            ),
            child: card,
          );
        },
      );
    });
  }

  Widget _nudge(Palette p) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.entries.length} entries live only on this phone', style: body(15, color: p.ink, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('If you lose or change the phone they are gone. Save a backup file now.',
                style: body(13, color: p.ink2)),
            Row(children: [
              TextButton(onPressed: () => shareBackup(s), child: const Text('Save backup')),
              TextButton(onPressed: s.dismissNudge, child: const Text('Not now')),
            ]),
          ]),
        ),
      );

  Widget _dayChip(Palette p, String iso) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(child: Text(dayLabelFor(iso).toUpperCase(), style: eyebrow(p.ink3))),
      );

  Widget _notice(Palette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Glass(
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: p.ink2),
              const SizedBox(width: 8),
              Flexible(child: Text(text, style: body(12.5, color: p.ink2))),
            ]),
          ),
        ),
      );

  Widget _assistantBubble(Palette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Glass(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text(text, style: body(14.5, color: p.ink)),
            ),
          ),
        ),
      );

  Widget _welcome(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _assistantBubble(
          p,
          'Salaam! Tell me what you spent, gave or got, in English or Roman Urdu. '
          'I will keep the record on your phone. You can connect Google Sheets any time from settings.',
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _examples)
            Press(
              onTap: () {
                _text.text = e;
                _text.selection = TextSelection.collapsed(offset: e.length);
                _focus.requestFocus();
              },
              child: Glass(
                radius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(e, style: body(13, color: p.ink2, weight: FontWeight.w500)),
              ),
            ),
        ]),
      ]);

  Widget _quickChips(Palette p) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, _text]),
      builder: (context, _) {
        final items = s.frequentPhrases;
        if (items.isEmpty || _text.text.isNotEmpty) return const SizedBox.shrink();
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
        return Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SizedBox(
          height: 42 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Press(
              onTap: () {
                HapticFeedback.selectionClick();
                _text.text = '${items[i]} ';
                _text.selection = TextSelection.collapsed(offset: _text.text.length);
                _focus.requestFocus();
              },
              child: Glass(
                radius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(items[i], style: body(13.5, color: p.ink2, weight: FontWeight.w600)),
              ),
            ),
          ),
        )));
      },
    );
  }

  Widget _composer(Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            radius: 999,
            padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  // Roman Urdu is full of "words" a dictionary would "fix" (dy -> money).
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  cursorColor: p.accent,
                  style: body(16, color: p.ink),
                  decoration: bareInput(hint: _listening ? 'Listening…' : 'mainy 500 rizwan ko dy ha', hintStyle: body(16, color: p.ink3)),
                ),
              ),
              const SizedBox(width: 6),
              Press(
                onTap: _toggleMic,
                label: _listening ? 'Stop listening' : 'Speak',
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _listening ? p.spentBg : p.field),
                  child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _listening ? p.spent : p.ink2, size: 22),
                ),
              ),
              const SizedBox(width: 6),
              Press(
                onTap: _send,
                label: 'Send',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                  child: _busy
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accentInk),
                        )
                      : Icon(Icons.arrow_upward_rounded, color: p.accentInk),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One thread item: what the user typed, then the card the app answered with.
class _EntryMessage extends StatelessWidget {
  const _EntryMessage({super.key, required this.entry, required this.state, required this.onEdit, required this.onDelete});
  final Entry entry;
  final AppState state;
  final void Function(Entry) onEdit, onDelete;

  String get _title {
    final e = entry;
    final m = state.money(e.amount);
    final who = e.person.isEmpty ? '' : e.person;
    return switch (e.type) {
      EntryType.expense => 'Spent $m${e.description.isEmpty ? '' : ' · ${e.description}'}',
      EntryType.given => who.isEmpty ? 'Gave $m' : 'Gave $m to $who',
      EntryType.received => who.isEmpty ? 'Got $m' : 'Got $m from $who',
      EntryType.income => 'Income $m${e.description.isEmpty ? '' : ' · ${e.description}'}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = entry;
    final sub = [
      e.category,
      if (e.time.isNotEmpty) e.time,
      if (state.connected && e.pending) 'waiting to sync',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(e),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: p.spent),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (e.note.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: p.accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Text(e.note, style: body(15, color: p.accentInk)),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Press(
                onTap: () => onEdit(e),
                label: 'Edit entry',
                child: Glass.flat(
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: p.typeBg(e.type), borderRadius: BorderRadius.circular(13)),
                      child: Icon(iconFor(e), size: 20, color: p.typeColor(e.type)),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_title, style: body(14.5, color: p.ink, weight: FontWeight.w600)),
                        Text(sub, style: body(12, color: p.ink3)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit_outlined, size: 16, color: p.ink3),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
