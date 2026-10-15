import 'dart:convert';

/// The app owner is always a member of every group, under this name.
const meName = 'You';

class Group {
  const Group({required this.id, required this.name, required this.members, required this.created});

  final String id;
  final String name;
  final List<String> members; // includes meName
  final String created; // ISO date

  Group copyWith({String? name, List<String>? members}) =>
      Group(id: id, name: name ?? this.name, members: members ?? this.members, created: created);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'members': members, 'created': created};

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: '${j['id']}',
        name: '${j['name']}',
        members: [for (final m in (j['members'] as List? ?? const [])) '$m'],
        created: '${j['created'] ?? ''}',
      );
}

class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.date,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.shares,
    this.settlement = false,
  });

  final String id;
  final String groupId;
  final String date; // yyyy-MM-dd
  final String description;
  final double amount;
  final String paidBy;

  /// How much of [amount] each person is responsible for. Sums to [amount].
  final Map<String, double> shares;

  /// A payment from [paidBy] to the one person in [shares], not a purchase.
  final bool settlement;

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'date': date,
        'description': description,
        'amount': amount,
        'paidBy': paidBy,
        'shares': shares,
        'settlement': settlement,
      };

  factory GroupExpense.fromJson(Map<String, dynamic> j) => GroupExpense(
        id: '${j['id']}',
        groupId: '${j['groupId']}',
        date: '${j['date']}',
        description: '${j['description']}',
        amount: (j['amount'] as num).toDouble(),
        paidBy: '${j['paidBy']}',
        shares: {for (final e in (j['shares'] as Map).entries) '${e.key}': (e.value as num).toDouble()},
        settlement: j['settlement'] == true,
      );

  String sharesJson() => jsonEncode(shares);
}

/// One suggested payment that settles part of the group.
class Debt {
  const Debt(this.from, this.to, this.amount);
  final String from, to;
  final double amount;
}

double round2(double v) => (v * 100).round() / 100;

/// Splits [amount] between [people] to the cent. Any leftover cent goes to the first person.
Map<String, double> equalShares(double amount, List<String> people) {
  if (people.isEmpty) return {};
  final cents = (amount * 100).round();
  final base = cents ~/ people.length;
  var extra = cents - base * people.length;
  final out = <String, double>{};
  for (final p in people) {
    final c = base + (extra > 0 ? 1 : 0);
    if (extra > 0) extra--;
    out[p] = c / 100;
  }
  return out;
}

/// Net position of every member. Positive: the group owes them. Negative: they owe the group.
Map<String, double> netBalances(Group g, Iterable<GroupExpense> expenses) {
  final net = {for (final m in g.members) m: 0.0};
  for (final e in expenses) {
    net[e.paidBy] = (net[e.paidBy] ?? 0) + e.amount;
    for (final s in e.shares.entries) {
      net[s.key] = (net[s.key] ?? 0) - s.value;
    }
  }
  return {for (final e in net.entries) e.key: round2(e.value)};
}

/// Fewest payments that settle everyone (greedy: biggest debtor pays biggest creditor).
List<Debt> simplifyDebts(Map<String, double> net) {
  final cred = [for (final e in net.entries) if (e.value > 0.005) MapEntry(e.key, e.value)]
    ..sort((a, b) => b.value.compareTo(a.value));
  final debt = [for (final e in net.entries) if (e.value < -0.005) MapEntry(e.key, -e.value)]
    ..sort((a, b) => b.value.compareTo(a.value));
  final out = <Debt>[];
  var i = 0, j = 0;
  final c = [for (final e in cred) e.value];
  final d = [for (final e in debt) e.value];
  while (i < cred.length && j < debt.length) {
    final pay = round2(c[i] < d[j] ? c[i] : d[j]);
    if (pay > 0) out.add(Debt(debt[j].key, cred[i].key, pay));
    c[i] -= pay;
    d[j] -= pay;
    if (c[i] < 0.005) i++;
    if (d[j] < 0.005) j++;
  }
  return out;
}
