import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/group.dart';
import 'package:spendline/services/group_parser.dart';

GroupExpense exp(String id, double amount, String paidBy, Map<String, double> shares, {bool settlement = false}) =>
    GroupExpense(
      id: id,
      groupId: 'g',
      date: '2026-10-15',
      description: 'x',
      amount: amount,
      paidBy: paidBy,
      shares: shares,
      settlement: settlement,
    );

void main() {
  const g = Group(id: 'g', name: 'Trip', members: ['You', 'Ali', 'Rizwan'], created: '2026-10-15');

  test('equal split sums exactly to the amount', () {
    final s = equalShares(100, ['You', 'Ali', 'Rizwan']);
    expect(s.values.fold(0.0, (a, b) => a + b), closeTo(100, 1e-9));
    expect(s['You'], 33.34);
    expect(s['Ali'], 33.33);
  });

  test('balances: you paid 3000 for three people', () {
    final net = netBalances(g, [exp('1', 3000, 'You', equalShares(3000, g.members))]);
    expect(net['You'], 2000);
    expect(net['Ali'], -1000);
    expect(net['Rizwan'], -1000);
  });

  test('simplify gives the fewest payments', () {
    final net = netBalances(g, [
      exp('1', 3000, 'You', equalShares(3000, g.members)),
      exp('2', 900, 'Ali', equalShares(900, g.members)),
    ]);
    // You: +3000-1000-300 = 1700, Ali: -1000+900-300 = -400, Rizwan: -1300
    expect(net['You'], 1700);
    final debts = simplifyDebts(net);
    expect(debts.length, 2);
    expect(debts.every((d) => d.to == 'You'), isTrue);
    expect(debts.fold(0.0, (a, d) => a + d.amount), 1700);
  });

  test('a settlement clears the balance', () {
    final all = [
      exp('1', 3000, 'You', equalShares(3000, g.members)),
      exp('2', 1000, 'Ali', {'You': 1000}, settlement: true),
    ];
    final net = netBalances(g, all);
    expect(net['Ali'], 0);
    expect(net['You'], 1000);
    expect(simplifyDebts(net).single.from, 'Rizwan');
  });

  test('json round trip', () {
    final e = exp('1', 50.5, 'Ali', {'You': 25.25, 'Ali': 25.25});
    final back = GroupExpense.fromJson(e.toJson());
    expect(back.shares['You'], 25.25);
    expect(back.paidBy, 'Ali');
  });

  group('group sentences', () {
    test('plain amount is split between everyone, you paid', () {
      final d = parseGroupSentence('dinner 3000', g);
      expect(d.amount, 3000);
      expect(d.description, 'Dinner');
      expect(d.paidBy, 'You');
      expect(d.participants, ['You', 'Ali', 'Rizwan']);
    });
    test('"ali ne taxi 800 diya"', () {
      final d = parseGroupSentence('ali ne taxi 800 diya', g);
      expect(d.paidBy, 'Ali');
      expect(d.amount, 800);
      expect(d.description, 'Taxi');
    });
    test('"with" limits who shares it', () {
      final d = parseGroupSentence('pizza 1200 with ali', g);
      expect(d.participants.toSet(), {'You', 'Ali'});
      expect(d.description, 'Pizza');
    });
    test('2k works', () {
      expect(parseGroupSentence('hotel 2k', g).amount, 2000);
    });
  });
}
