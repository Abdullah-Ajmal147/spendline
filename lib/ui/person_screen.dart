import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/entry.dart';
import '../services/parser.dart';
import '../state/app_state.dart';
import 'entry_editor.dart';
import 'glass.dart';
import 'theme.dart';

/// Everything with one person, their running balance, and a WhatsApp reminder.
class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.state, required this.name});
  final AppState state;
  final String name;

  List<Entry> get _entries => [
        for (final e in state.entries)
          if (e.person.trim().toLowerCase() == name.toLowerCase() &&
              (e.type == EntryType.given || e.type == EntryType.received))
            e,
      ];

  double get _balance => _entries.fold(0.0, (s, e) => s + (e.type == EntryType.given ? e.amount : -e.amount));

  Future<void> _remind(double owed) async {
    final since = _entries.where((e) => e.type == EntryType.given).map((e) => e.date).fold<String>('', (a, b) => a.isEmpty || b.compareTo(a) < 0 ? b : a);
    final amount = state.money(owed);
    final msg = 'Assalam o Alaikum $name, aap ke zimme $amount baqi hain'
        '${since.isEmpty ? '' : ' (${dayLabelFor(since)} se)'}. Jab suhoolat ho wapas kar dijiye ga, shukriya.\n\n'
        'Hi $name, a gentle reminder that $amount is pending. Thank you!';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Fall through to the share sheet.
    }
    await SharePlus.instance.share(ShareParams(text: msg));
  }

  Future<void> _settle(double balance) async {
    final owedToMe = balance > 0;
    await state.add(
      Draft(
        type: owedToMe ? EntryType.received : EntryType.given,
        amount: balance.abs(),
        person: name,
        category: 'Lending',
        description: owedToMe ? 'From $name · settled' : 'To $name · settled',
        date: isoDate(DateTime.now()),
        confidence: 1,
      ),
      'Settled with $name',
    );
    toast('Marked as settled');
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
            listenable: state,
            builder: (context, _) {
              final list = _entries;
              final bal = _balance;
              final line = bal > 0
                  ? 'owes you'
                  : bal < 0
                      ? 'you owe'
                      : 'all settled';
              final color = bal > 0 ? p.lent : bal < 0 ? p.recv : p.ink3;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                    Row(children: [
                      Press(
                        onTap: () => Navigator.pop(context),
                        label: 'Back',
                        child: Glass(radius: 999, padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_back_rounded, size: 20, color: p.ink)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(name, style: display(22, color: p.ink), overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 18),
                    Glass(
                      radius: 30,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(line.toUpperCase(), style: eyebrow(color)),
                        const SizedBox(height: 8),
                        Text(state.money(bal.abs()), style: display(46, color: p.ink)),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (bal > 0)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _remind(bal),
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: const Text('Remind'),
                              ),
                            ),
                          if (bal > 0 && bal != 0) const SizedBox(width: 8),
                          if (bal != 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _settle(bal),
                                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                                child: const Text('Mark settled'),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Text('History', style: display(18, color: p.ink)),
                    const SizedBox(height: 8),
                    if (list.length > 100)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Showing the latest 100 of ${list.length}. The balance counts all of them.',
                            style: body(12.5, color: p.ink3)),
                      ),
                    if (list.isEmpty)
                      Text('Nothing recorded with $name yet.', style: body(14, color: p.ink2))
                    else
                      Glass(
                        radius: 26,
                        padding: const EdgeInsets.all(6),
                        child: Column(children: [
                          for (final e in list.take(100))
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              child: Row(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(color: p.typeBg(e.type), borderRadius: BorderRadius.circular(13)),
                                  child: Icon(
                                    e.type == EntryType.given ? Icons.north_east_rounded : Icons.south_west_rounded,
                                    size: 19,
                                    color: p.typeColor(e.type),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.type == EntryType.given ? 'You gave' : 'You got',
                                        style: body(15, color: p.ink, weight: FontWeight.w600)),
                                    Text(dayLabelFor(e.date), style: body(12.5, color: p.ink3)),
                                  ]),
                                ),
                                Text(state.money(e.amount),
                                    style: display(15.5, color: p.typeColor(e.type), weight: FontWeight.w600)),
                              ]),
                            ),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
