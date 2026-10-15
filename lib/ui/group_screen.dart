import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/group.dart';
import '../services/group_parser.dart';
import '../services/parser.dart';
import '../state/app_state.dart';
import 'entry_editor.dart' show dayLabelFor;
import 'glass.dart';
import 'theme.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.state, required this.groupId});
  final AppState state;
  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _text = TextEditingController();
  AppState get s => widget.state;

  Group? get _group {
    for (final g in s.groups) {
      if (g.id == widget.groupId) return g;
    }
    return null;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addFromText() async {
    final g = _group;
    final t = _text.text.trim();
    if (g == null || t.isEmpty) return;
    _text.clear();
    await _openEditor(g, parseGroupSentence(t, g));
  }

  Future<void> _openEditor(Group g, GroupDraft draft) async {
    final r = await showModalBottomSheet<_ExpenseInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (_) => _ExpenseEditor(state: s, group: g, draft: draft),
    );
    if (r == null) return;
    final e = await s.addGroupExpense(
      g,
      description: r.description,
      amount: r.amount,
      paidBy: r.paidBy,
      shares: r.shares,
      date: r.date,
    );
    toast('Added', undo: () => s.removeGroupExpense(e));
  }

  Future<void> _settle(Group g, Debt d) async {
    await s.addGroupExpense(
      g,
      description: 'Settled up',
      amount: d.amount,
      paidBy: d.from,
      shares: {d.to: d.amount},
      date: isoDate(DateTime.now()),
      settlement: true,
    );
    toast('${d.from} paid ${d.to} ${s.money(d.amount)}');
  }

  String _name(String n) => n == meName ? 'You' : n;

  Future<void> _share(Group g) async {
    String who(String n) => n == meName ? 'Me' : n;
    final all = s.expensesOf(g);
    final net = netBalances(g, all);
    final debts = simplifyDebts(net);
    final total = all.where((e) => !e.settlement).fold(0.0, (a, e) => a + e.amount);
    final b = StringBuffer('${g.name} · expenses\nTotal spent: ${s.money(total)}\n\n');
    if (debts.isEmpty) {
      b.writeln('All settled up.');
    } else {
      b.writeln('To settle up:');
      for (final d in debts) {
        b.writeln('• ${who(d.from)} pays ${who(d.to)} ${s.money(d.amount)}');
      }
    }
    b.writeln('\nExpenses:');
    for (final e in all.where((e) => !e.settlement).take(30)) {
      b.writeln('• ${e.description} ${s.money(e.amount)} (${who(e.paidBy)} paid)');
    }
    await SharePlus.instance.share(ShareParams(text: b.toString().trim(), subject: g.name));
  }

  Future<void> _addMember(Group g) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a person'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    final n = cap(name);
    if (g.members.any((m) => m.toLowerCase() == n.toLowerCase())) return;
    await s.updateGroup(g.copyWith(members: [...g.members, n]));
  }

  Future<void> _delete(Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${g.name}"?'),
        content: const Text('All its expenses are deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await s.removeGroup(g);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final g = _group;
              if (g == null) return const SizedBox.shrink();
              final all = s.expensesOf(g);
              final net = netBalances(g, all);
              final debts = simplifyDebts(net);
              final mine = net[meName] ?? 0;
              final line = mine > 0.005
                  ? 'You are owed'
                  : mine < -0.005
                      ? 'You owe'
                      : 'All settled up';
              final color = mine > 0.005 ? p.recv : mine < -0.005 ? p.lent : p.ink3;

              return Column(children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 20), children: [
                        Row(children: [
                          Press(
                            onTap: () => Navigator.pop(context),
                            label: 'Back',
                            child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(g.name, style: display(22, color: p.ink), overflow: TextOverflow.ellipsis)),
                          IconButton(onPressed: () => _share(g), icon: Icon(Icons.ios_share_rounded, color: p.ink), tooltip: 'Share summary'),
                          PopupMenuButton<String>(
                            onSelected: (v) => v == 'add' ? _addMember(g) : _delete(g),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'add', child: Text('Add a person')),
                              PopupMenuItem(value: 'del', child: Text('Delete group')),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Glass(
                          radius: 30,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(line.toUpperCase(), style: eyebrow(color)),
                            const SizedBox(height: 6),
                            if (mine.abs() > 0.005) Text(s.money(mine.abs()), style: display(42, color: p.ink)),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final m in g.members) _memberChip(p, m, net[m] ?? 0),
                            ]),
                          ]),
                        ),
                        if (debts.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text('Settle up', style: display(18, color: p.ink)),
                          const SizedBox(height: 8),
                          Glass(
                            radius: 24,
                            padding: const EdgeInsets.all(8),
                            child: Column(children: [
                              for (final d in debts)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                                  child: Row(children: [
                                    Expanded(
                                      child: Text('${_name(d.from)} → ${_name(d.to)}',
                                          style: body(15, color: p.ink, weight: FontWeight.w600)),
                                    ),
                                    Text(s.money(d.amount), style: display(15.5, color: p.ink)),
                                    TextButton(onPressed: () => _settle(g, d), child: const Text('Settle')),
                                  ]),
                                ),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text('Expenses', style: display(18, color: p.ink)),
                        const SizedBox(height: 8),
                        if (all.isEmpty)
                          Text('Nothing yet. Type below, e.g. "dinner 3000" or "ali ne taxi 800 diya".',
                              style: body(14, color: p.ink2))
                        else
                          for (final e in all) _expenseRow(p, g, e),
                      ]),
                    ),
                  ),
                ),
                _composer(p, g),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _memberChip(Palette p, String m, double n) {
    final text = n > 0.005
        ? 'gets ${s.money(n)}'
        : n < -0.005
            ? 'owes ${s.money(-n)}'
            : 'settled';
    final c = n > 0.005 ? p.recv : n < -0.005 ? p.lent : p.ink3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m, style: body(13.5, color: p.ink, weight: FontWeight.w700)),
        Text(text, style: body(12, color: c, weight: FontWeight.w600)),
      ]),
    );
  }

  Widget _expenseRow(Palette p, Group g, GroupExpense e) {
    final myShare = e.shares[meName] ?? 0;
    final String title;
    final String sub;
    if (e.settlement) {
      final to = e.shares.keys.isEmpty ? '' : e.shares.keys.first;
      title = '${_name(e.paidBy)} paid ${_name(to)}';
      sub = dayLabelFor(e.date);
    } else {
      title = e.description;
      sub = '${_name(e.paidBy)} paid ${s.money(e.amount)} · ${dayLabelFor(e.date)}';
    }
    final trailing = e.settlement
        ? s.money(e.amount)
        : myShare > 0
            ? 'your share ${s.money(myShare)}'
            : 'not involved';
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        s.removeGroupExpense(e);
        toast('Deleted', undo: () => s.restoreGroupExpense(e));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: p.spent),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Glass.flat(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: e.settlement ? p.recvBg : p.field, borderRadius: BorderRadius.circular(13)),
              child: Icon(e.settlement ? Icons.handshake_rounded : Icons.receipt_long_rounded,
                  size: 20, color: e.settlement ? p.recv : p.ink2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(15, color: p.ink, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(sub, style: body(12, color: p.ink3), overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            Text(trailing, style: body(12.5, color: p.ink2, weight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _composer(Palette p, Group g) => Padding(
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
                    onSubmitted: (_) => _addFromText(),
                    textInputAction: TextInputAction.send,
                    autocorrect: false,
                    enableSuggestions: false,
                    cursorColor: p.accent,
                    style: body(16, color: p.ink),
                    decoration: bareInput(hint: 'dinner 3000 with ali', hintStyle: body(16, color: p.ink3)),
                  ),
                ),
                Press(
                  onTap: _addFromText,
                  label: 'Add expense',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                    child: Icon(Icons.arrow_upward_rounded, color: p.accentInk),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _ExpenseInput {
  _ExpenseInput(this.description, this.amount, this.paidBy, this.shares, this.date);
  final String description;
  final double amount;
  final String paidBy;
  final Map<String, double> shares;
  final String date;
}

class _ExpenseEditor extends StatefulWidget {
  const _ExpenseEditor({required this.state, required this.group, required this.draft});
  final AppState state;
  final Group group;
  final GroupDraft draft;

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  late final _desc = TextEditingController(text: widget.draft.description);
  late final _amount = TextEditingController(text: widget.draft.amount > 0 ? '${widget.draft.amount}'.replaceFirst(RegExp(r'\.0$'), '') : '');
  late String _paidBy = widget.draft.paidBy;
  late String _date = widget.draft.date;
  late final Set<String> _in = {...widget.draft.participants};
  final Map<String, TextEditingController> _exact = {};
  bool _isExact = false;

  double get _total => double.tryParse(_amount.text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _exact.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _exactFor(String m) => _exact.putIfAbsent(m, () => TextEditingController());

  Map<String, double> _shares() {
    if (!_isExact) {
      return equalShares(_total, [for (final m in widget.group.members) if (_in.contains(m)) m]);
    }
    return {
      for (final m in widget.group.members)
        if ((double.tryParse(_exactFor(m).text) ?? 0) > 0) m: double.parse(_exactFor(m).text),
    };
  }

  String? get _problem {
    if (_total <= 0) return 'Enter the amount';
    if (!_isExact && _in.isEmpty) return 'Pick at least one person';
    if (_isExact) {
      final sum = _shares().values.fold(0.0, (a, b) => a + b);
      final left = round2(_total - sum);
      if (left.abs() > 0.009) return left > 0 ? '${left.toString().replaceFirst(RegExp(r'\.0$'), '')} still to assign' : 'Shares are ${(-left)} too much';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final members = widget.group.members;
    final equal = equalShares(_total, [for (final m in members) if (_in.contains(m)) m]);
    final problem = _problem;
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
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Add expense', style: display(20, color: p.ink)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _desc,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'What for'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _amount,
                        autofocus: widget.draft.amount <= 0,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(hintText: '0', prefixText: '${widget.state.currency} '),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text('PAID BY', style: eyebrow(p.ink3, size: 10.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final m in members)
                      ChoiceChip(
                        label: Text(m),
                        selected: _paidBy == m,
                        onSelected: (_) => setState(() => _paidBy = m),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('SPLIT', style: eyebrow(p.ink3, size: 10.5)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Equally')),
                        ButtonSegment(value: true, label: Text('By amount')),
                      ],
                      selected: {_isExact},
                      onSelectionChanged: (v) => setState(() => _isExact = v.first),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  for (final m in members)
                    Row(children: [
                      if (!_isExact)
                        Checkbox(
                          value: _in.contains(m),
                          onChanged: (v) => setState(() => v == true ? _in.add(m) : _in.remove(m)),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(child: Text(m, style: body(15, color: p.ink, weight: FontWeight.w500))),
                      if (!_isExact)
                        Text(_in.contains(m) ? widget.state.money(equal[m] ?? 0) : '–', style: body(14, color: p.ink2))
                      else
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _exactFor(m),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.right,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(hintText: '0', isDense: true),
                          ),
                        ),
                    ]),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(problem, style: body(13, color: p.lent)),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.tryParse(_date) ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 1, 12, 31),
                        );
                        if (d != null) setState(() => _date = isoDate(d));
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(dayLabelFor(_date)),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
                      onPressed: problem != null
                          ? null
                          : () => Navigator.pop(
                                context,
                                _ExpenseInput(_desc.text, _total, _paidBy, _shares(), _date),
                              ),
                      child: const Text('Save'),
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
}
