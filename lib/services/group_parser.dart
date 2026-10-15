import '../models/group.dart';
import 'parser.dart';

/// A guess at a group expense from one sentence. Always shown for confirmation.
class GroupDraft {
  GroupDraft({
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.participants,
    required this.date,
  });

  String description;
  double amount;
  String paidBy;
  List<String> participants;
  String date;
}

const _noise = {
  'ne', 'paid', 'pay', 'diya', 'diye', 'di', 'with', 'ke', 'sath', 'saath', 'split', 'between', 'among',
  'and', 'aur', 'for', 'the', 'a', 'rs', 'pkr', 'by', 'sab', 'sabmein', 'barabar', 'equally', 'all',
  'spent', 'bought', 'kal', 'aaj', 'today', 'yesterday', 'ko', 'se', 'ka', 'ki', 'hai', 'ha', 'liye',
};

/// "dinner 3000", "ali ne taxi 800 diya", "dinner 3000 with ali and rizwan", "paid by ali 1200 pizza"
GroupDraft parseGroupSentence(String text, Group g, {DateTime? now}) {
  final base = parseEntry(text, now: now);
  final lower = ' ${text.toLowerCase().replaceAll(RegExp(r'[,;]'), ' ')} ';
  final others = [for (final m in g.members) if (m != meName) m];

  bool mentions(String name) => RegExp('(?<![\\p{L}])${RegExp.escape(name.toLowerCase())}(?![\\p{L}])', unicode: true).hasMatch(lower);

  var paidBy = meName;
  for (final m in others) {
    final n = RegExp.escape(m.toLowerCase());
    if (RegExp('(?<![\\p{L}])$n\\s+(ne|paid|pay)\\b', unicode: true).hasMatch(lower) ||
        RegExp('paid by\\s+$n\\b', unicode: true).hasMatch(lower)) {
      paidBy = m;
      break;
    }
  }

  // Names after "with / ke sath / between" mean only those people share it; otherwise everyone does.
  final named = [for (final m in others) if (mentions(m)) m];
  final scoped = RegExp(r'\b(with|ke sath|ke saath|between|among)\b').hasMatch(lower);
  List<String> participants;
  if (scoped && named.isNotEmpty) {
    participants = {meName, paidBy, ...named}.toList();
  } else {
    participants = List.of(g.members);
  }

  final skip = {for (final m in g.members) ...m.toLowerCase().split(' ')};
  final words = lower
      .split(RegExp(r"[^\p{L}\p{N}']+", unicode: true))
      .where((w) => w.isNotEmpty && !_noise.contains(w) && !skip.contains(w) && double.tryParse(w) == null)
      .where((w) => !RegExp(r'^\d+(k|st|nd|rd|th)?$').hasMatch(w))
      .toList();
  final desc = words.isEmpty ? '' : cap(words.take(4).join(' '));

  return GroupDraft(
    description: desc,
    amount: base.amount,
    paidBy: paidBy,
    participants: participants,
    date: base.date,
  );
}
