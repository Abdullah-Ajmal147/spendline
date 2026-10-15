import 'package:flutter/material.dart';

import '../models/group.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'group_screen.dart';
import 'theme.dart';

/// Splitwise-style groups: trips, flat, office lunch.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, required this.state});
  final AppState state;

  Future<void> _create(BuildContext context) async {
    final g = await showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (_) => _NewGroupSheet(state: state),
    );
    if (g != null && context.mounted) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(state: state, groupId: g.id)));
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
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                  Row(children: [
                    Press(
                      onTap: () => Navigator.pop(context),
                      label: 'Back',
                      child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Groups', style: display(22, color: p.ink))),
                    FilledButton.icon(
                      onPressed: () => _create(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New group'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  if (state.groups.isEmpty)
                    Glass(
                      radius: 26,
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Split costs with friends', style: display(18, color: p.ink)),
                        const SizedBox(height: 6),
                        Text(
                          'Make a group (trip, flat, office lunch), add who paid and who shares, and the app '
                          'works out who owes whom. You keep the record on your phone and can send everyone '
                          'the summary on WhatsApp.',
                          style: body(14, color: p.ink2),
                        ),
                      ]),
                    ),
                  for (final g in state.groups) _tile(context, p, g),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, Palette p, Group g) {
    final bal = state.myBalance(g);
    final line = bal > 0.005
        ? 'You are owed ${state.money(bal)}'
        : bal < -0.005
            ? 'You owe ${state.money(-bal)}'
            : state.expensesOf(g).isEmpty
                ? 'No expenses yet'
                : 'All settled up';
    final color = bal > 0.005 ? p.recv : bal < -0.005 ? p.lent : p.ink3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Press(
        onTap: () => Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => GroupScreen(state: state, groupId: g.id))),
        label: 'Open ${g.name}',
        child: Glass(
          radius: 24,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.groups_rounded, color: p.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, style: body(16, color: p.ink, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(g.members.map((m) => m).join(', '),
                    style: body(12.5, color: p.ink3), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            Text(line, textAlign: TextAlign.right, style: body(13, color: color, weight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet({required this.state});
  final AppState state;

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _name = TextEditingController();
  final _member = TextEditingController();
  final _members = <String>[];

  @override
  void dispose() {
    _name.dispose();
    _member.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return;
    final shown = n[0].toUpperCase() + n.substring(1);
    if (!_members.any((m) => m.toLowerCase() == shown.toLowerCase()) && shown != meName) {
      setState(() => _members.add(shown));
    }
    _member.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final suggestions = widget.state.knownNames.where((n) => !_members.contains(n)).take(8).toList();
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
                  Text('New group', style: display(22, color: p.ink)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Group name, e.g. Murree trip'),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _member,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: _add,
                        decoration: const InputDecoration(hintText: 'Add a person'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: () => _add(_member.text), icon: const Icon(Icons.add_rounded)),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    const Chip(label: Text(meName)),
                    for (final m in _members)
                      InputChip(label: Text(m), onDeleted: () => setState(() => _members.remove(m))),
                  ]),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('From your ledger', style: body(12, color: p.ink3)),
                    Wrap(spacing: 8, children: [
                      for (final n in suggestions) ActionChip(label: Text(n), onPressed: () => _add(n)),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () async {
                      _add(_member.text);
                      final g = await widget.state.addGroup(_name.text, _members);
                      if (context.mounted) Navigator.pop(context, g);
                    },
                    child: const Text('Create group'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
