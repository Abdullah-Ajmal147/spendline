import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../services/parser.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'theme.dart';

String dayLabelFor(String iso) {
  final now = DateTime.now();
  if (iso == isoDate(now)) return 'Today';
  if (iso == isoDate(DateTime(now.year, now.month, now.day - 1))) return 'Yesterday';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

/// Bottom sheet to check or fix a parsed entry. Returns the edited draft, or null if dismissed.
Future<Draft?> showEntryEditor(
  BuildContext context,
  AppState state,
  Draft draft, {
  required String title,
  required String action,
  String? hint,
}) =>
    showModalBottomSheet<Draft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (_) => _EntryEditor(state: state, draft: draft.copy(), title: title, action: action, hint: hint),
    );

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.state, required this.draft, required this.title, required this.action, this.hint});
  final AppState state;
  final Draft draft;
  final String title, action;
  final String? hint;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final Draft d = widget.draft;
  late final _amount = TextEditingController(text: d.amount > 0 ? _plain(d.amount) : '');
  late final _desc = TextEditingController(text: d.description);
  late final _person = TextEditingController(text: d.person);

  static String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _person.dispose();
    super.dispose();
  }

  void _cycleType() {
    d.type = EntryType.values[(EntryType.values.indexOf(d.type) + 1) % EntryType.values.length];
    if (d.needsPerson) {
      d.category = 'Lending';
    } else if (d.type == EntryType.income) {
      d.category = 'Income';
    } else if (d.category == 'Lending' || d.category == 'Income') {
      d.category = 'Other';
    }
    final prefix = RegExp(r'^(To|From) ');
    if (prefix.hasMatch(d.description)) {
      d.description = d.description.replaceFirst(prefix, d.type == EntryType.received ? 'From ' : 'To ');
      _desc.text = d.description;
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(d.date) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => d.date = isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fieldStyle = body(15, color: p.ink, weight: FontWeight.w500);
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
                  Text(widget.title, style: display(20, color: p.ink)),
                  if (widget.hint != null) ...[
                    const SizedBox(height: 4),
                    Text(widget.hint!, style: body(13, color: p.ink2)),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    TypePill(type: d.type, onTap: _cycleType),
                    const Spacer(),
                    Text(widget.state.currency, style: body(15, color: p.ink2, weight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _amount,
                        textAlign: TextAlign.right,
                        autofocus: d.amount <= 0,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: display(28, color: p.ink),
                        cursorColor: p.accent,
                        decoration: bareInput(hint: '0', hintStyle: display(28, color: p.ink3)),
                        onChanged: (v) => setState(() => d.amount = double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _field(p, 'For', TextField(
                        controller: _desc,
                        style: fieldStyle,
                        decoration: bareInput(),
                        onChanged: (v) => d.description = v,
                      )),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _field(p, 'Person', TextField(
                        controller: _person,
                        style: fieldStyle,
                        textCapitalization: TextCapitalization.words,
                        decoration: bareInput(),
                        onChanged: (v) => d.person = v.trim(),
                      )),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: PopupMenuButton<String>(
                        initialValue: d.category,
                        onSelected: (c) => setState(() => d.category = c),
                        itemBuilder: (_) => [for (final c in catList) PopupMenuItem(value: c, child: Text(c))],
                        child: _field(p, 'Category', Row(children: [
                          Expanded(child: Text(d.category, style: fieldStyle, overflow: TextOverflow.ellipsis)),
                          Icon(Icons.expand_more_rounded, size: 18, color: p.ink3),
                        ])),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _pickDate,
                        child: _field(p, 'Date', Row(children: [
                          Expanded(child: Text(dayLabelFor(d.date), style: fieldStyle, overflow: TextOverflow.ellipsis)),
                          Icon(Icons.calendar_today_rounded, size: 15, color: p.ink3),
                        ])),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: d.amount > 0 ? () => Navigator.pop(context, d) : null,
                    child: Text(widget.action),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(Palette p, String label, Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
        decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: eyebrow(p.ink3, size: 10.5)),
          const SizedBox(height: 3),
          child,
        ]),
      );
}
