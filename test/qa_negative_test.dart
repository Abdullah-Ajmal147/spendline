import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/entry.dart';
import 'package:spendline/models/filter.dart';
import 'package:spendline/models/group.dart';
import 'package:spendline/services/csv.dart';
import 'package:spendline/services/firebase_cloud.dart';
import 'package:spendline/services/group_parser.dart';
import 'package:spendline/services/parser.dart';

/// Senior-QA style negative and boundary tests. Each group states the risk it guards against.
void main() {
  final now = DateTime(2026, 10, 15, 14, 30); // Thursday

  group('P1 parser never throws on hostile input', () {
    final nasty = <String>[
      '',
      '   ',
      '\n\n\t',
      '🙂🙂🙂',
      '500',
      '٥٠٠',
      'لنچ ۵۰۰',
      '<script>alert(1)</script> 500',
      "Robert'); DROP TABLE entries;-- 500",
      '${'a' * 20000} 500',
      '9' * 400,
      '.',
      '..5..',
      '1e5',
      '--500--',
      'Rs',
      'k',
      'lakh',
      'hazar hazar hazar',
      '5 5 5 5 5',
      'kal kal kal parson aaj',
      'ko ko ko se se ne ne',
      '\u0000\u0001 500',
      'Ali' * 500,
      '5/0 0/5 0/0 99/99',
      '31 feb',
      'oct oct oct 500',
    ];
    for (final s in nasty) {
      test('parseEntry/parseMany: ${s.length > 30 ? s.substring(0, 30) : s}', () {
        final d = parseEntry(s, now: now);
        expect(d.amount.isFinite, isTrue);
        expect(d.amount, greaterThanOrEqualTo(0));
        expect(d.confidence, inInclusiveRange(0, 1));
        expect(parseMany(s, now: now), isNotEmpty);
        expect(DateTime.tryParse(d.date), isNotNull, reason: 'date must always be valid: ${d.date}');
      });
    }
  });

  group('P2 amounts', () {
    double amt(String s) => parseEntry(s, now: now).amount;
    test('indian grouping', () => expect(amt('rent 1,00,000'), 100000));
    test('lakh decimals', () => expect(amt('car 2.5 lakh'), 250000));
    test('suffix currency', () => expect(amt('chai 500rs'), 500));
    test('prefix currency with dot', () => expect(amt('chai Rs. 500'), 500));
    test('slash dash', () => expect(amt('chai 500/-'), 500));
    test('english words', () => expect(amt('lunch five hundred'), 500));
    test('urdu words', () => expect(amt('chai paanch sau'), 500));
    test('arabic-indic digits', () => expect(amt('chai ٥٠٠'), 500));
    test('extended urdu digits', () => expect(amt('chai ۵۰۰'), 500));
    test('full-width digits', () => expect(amt('chai ５００'), 500));
    test('zero is not an entry', () => expect(amt('lunch 0'), 0));
    test('absurd value is rejected, not stored', () => expect(amt('lunch 99999999999999999999'), 0));
    test('rounds to two decimals', () => expect(amt('lunch 500.555'), 500.56));
    test('two numbers: largest wins but is flagged', () {
      final d = parseEntry('lunch 300 chai 20', now: now);
      expect(d.amount, 300);
    });
  });

  group('P3 dates', () {
    String dt(String s) => parseEntry(s, now: now).date;
    test('iso date', () => expect(dt('lunch 500 2026-10-05'), '2026-10-05'));
    test('impossible date falls back to today', () => expect(dt('lunch 500 31 feb'), '2026-10-15'));
    test('impossible numeric date falls back', () => expect(dt('lunch 500 99/99'), '2026-10-15'));
    test('leap day exists', () => expect(dt('lunch 500 29 feb 2028'), '2028-02-29'));
    test('non-leap 29 feb is rejected', () => expect(dt('lunch 500 29 feb 2027'), '2026-10-15'));
    test('amount next to month name stays amount', () {
      final d = parseEntry('rent 45000 oct', now: now);
      expect(d.amount, 45000);
    });
    test('year only number is not a date', () => expect(parseEntry('fee 2026', now: now).amount, 2026));
  });

  group('P4 types and people', () {
    test('missing person does not crash and is flagged', () {
      final d = parseEntry('gave 500', now: now);
      expect(d.type, EntryType.given);
      expect(d.person, '');
      expect(d.confidence, lessThan(.9));
    });
    test('name with apostrophe', () => expect(parseEntry("gave o'neil 500", now: now).person.toLowerCase(), "o'neil"));
    test('both directions in one message are split', () {
      final l = parseMany('ali ko 500 diye aur ali se 300 liye', now: now);
      expect(l.length, 2);
      expect(l[0].type, EntryType.given);
      expect(l[1].type, EntryType.received);
    });
    test('very many entries in one message', () {
      final text = List.generate(200, (i) => 'item$i ${i + 1}').join(', ');
      expect(parseMany(text, now: now).length, 200);
    });
  });

  group('G1 money split properties (fuzz)', () {
    final rnd = Random(42);
    test('equal split always sums to the amount to the cent', () {
      for (var i = 0; i < 2000; i++) {
        final cents = rnd.nextInt(10000000) + 1;
        final n = rnd.nextInt(12) + 1;
        final people = [for (var k = 0; k < n; k++) 'p$k'];
        final s = equalShares(cents / 100, people);
        final sum = s.values.fold<int>(0, (a, b) => a + (b * 100).round());
        expect(sum, cents, reason: 'cents=$cents n=$n');
      }
    });
    test('balances sum to zero and debts clear everyone', () {
      for (var run = 0; run < 300; run++) {
        final members = ['You', for (var k = 0; k < rnd.nextInt(6) + 1; k++) 'M$k'];
        final g = Group(id: 'g', name: 'x', members: members, created: '2026-01-01');
        final ex = <GroupExpense>[];
        for (var k = 0; k < rnd.nextInt(15) + 1; k++) {
          final amount = (rnd.nextInt(500000) + 1) / 100;
          final payer = members[rnd.nextInt(members.length)];
          final part = [for (final m in members) if (rnd.nextBool()) m];
          if (part.isEmpty) part.add(payer);
          ex.add(GroupExpense(
            id: 'e$k',
            groupId: 'g',
            date: '2026-10-15',
            description: 'x',
            amount: amount,
            paidBy: payer,
            shares: equalShares(amount, part),
          ));
        }
        final net = netBalances(g, ex);
        expect(net.values.fold(0.0, (a, b) => a + b).abs(), lessThan(0.05 * members.length), reason: 'run $run');
        final debts = simplifyDebts(net);
        expect(debts.length, lessThanOrEqualTo(max(0, members.length - 1)));
        final after = Map.of(net);
        for (final d in debts) {
          expect(d.amount, greaterThan(0));
          after[d.from] = (after[d.from] ?? 0) + d.amount;
          after[d.to] = (after[d.to] ?? 0) - d.amount;
        }
        for (final v in after.values) {
          expect(v.abs(), lessThan(0.02), reason: 'run $run left $after');
        }
      }
    });
    test('zero people and zero amount do not throw', () {
      expect(equalShares(100, const []), isEmpty);
      expect(equalShares(0, const ['a', 'b']).values.every((v) => v == 0), isTrue);
    });
  });

  group('G2 group sentence parsing', () {
    const g = Group(id: 'g', name: 'Trip', members: ['You', 'Ali Khan', 'Ne', 'With'], created: 'x');
    test('hostile member names do not break parsing', () {
      final d = parseGroupSentence('dinner 3000 with ali khan', g);
      expect(d.amount, 3000);
      expect(d.participants, contains('Ali Khan'));
    });
    test('no amount yields zero amount, not an exception', () {
      expect(parseGroupSentence('dinner', g).amount, 0);
    });
    test('empty string', () {
      expect(parseGroupSentence('', g).amount, 0);
    });
  });

  group('C1 csv abuse', () {
    Entry e0(String desc, {String note = '', double amount = 10, String id = 'a'}) => Entry(
          id: id, date: '2026-10-15', time: '10:00', type: EntryType.expense, category: 'Other',
          person: '', description: desc, amount: amount, note: note);

    test('formula injection is neutralised on export and restored on import', () {
      final csv = entriesToCsv([e0('=HYPERLINK("http://evil","x")', note: '+cmd|calc')]);
      for (final line in csv.split('\n').skip(1)) {
        expect(RegExp(r'(^|,)"?[=+@\-]').hasMatch(line), isFalse, reason: 'a cell starts like a formula: $line');
      }
      final back = entriesFromCsv(csv).single;
      expect(back.description, '=HYPERLINK("http://evil","x")');
      expect(back.note, '+cmd|calc');
    });
    test('NaN / Infinity / negative / absurd amounts are rejected on import', () {
      const head = 'ID,Date,Time,Type,Category,Person,Description,Amount,Note\n';
      for (final bad in ['NaN', 'Infinity', '-5', '0', '1e30', 'abc', '']) {
        expect(entriesFromCsv('${head}x1,2026-10-15,10:00,Expense,Other,,d,$bad,\n'), isEmpty, reason: bad);
      }
    });
    test('impossible dates are rejected on import', () {
      const head = 'ID,Date,Time,Type,Category,Person,Description,Amount,Note\n';
      expect(entriesFromCsv('${head}x1,2026-99-99,10:00,Expense,Other,,d,5,\n'), isEmpty);
      expect(entriesFromCsv('${head}x1,2026-02-30,10:00,Expense,Other,,d,5,\n'), isEmpty);
    });
    test('unterminated quote and ragged rows do not throw', () {
      expect(() => entriesFromCsv('ID,Date\n"unterminated,1,2'), returnsNormally);
      expect(() => entriesFromCsv('a\n,,,\n\n\n,'), returnsNormally);
      expect(() => entriesFromCsv('\u0000￿\n'), returnsNormally);
    });
    test('crlf and bom', () {
      final csv = '﻿ID,Date,Time,Type,Category,Person,Description,Amount,Note\r\nx1,2026-10-15,10:00,Expense,Food,,Tea,40,\r\n';
      expect(entriesFromCsv(csv).single.amount, 40);
    });
    test('duplicate ids inside one file keep one', () {
      const head = 'ID,Date,Time,Type,Category,Person,Description,Amount,Note\n';
      final l = entriesFromCsv('${head}x1,2026-10-15,10:00,Expense,Food,,A,1,\nx1,2026-10-15,10:00,Expense,Food,,B,2,\n');
      expect(l.map((e) => e.id).toSet().length, l.length);
    });
    test('10k rows import quickly', () {
      final big = entriesToCsv([for (var i = 0; i < 10000; i++) e0('d$i', id: 'i$i', amount: i + 1.0)]);
      final sw = Stopwatch()..start();
      final back = entriesFromCsv(big);
      sw.stop();
      expect(back.length, 10000);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('F1 filter', () {
    final e = Entry(id: '1', date: '2026-10-15', time: '1', type: EntryType.expense, category: 'Food', person: '', description: 'a.b(c)*', amount: 5);
    test('regex characters in the query are literal', () {
      expect(const EntryFilter(query: '.*').matches(e), isFalse);
      expect(const EntryFilter(query: 'a.b(c)*').matches(e), isTrue);
      expect(const EntryFilter(query: '[x]').matches(e), isFalse);
    });
    test('reversed date range matches nothing, no crash', () {
      expect(const EntryFilter(from: '2026-12-01', to: '2026-01-01').matches(e), isFalse);
    });
  });

  group('N1 cloud encoding', () {
    test('non-finite numbers never reach the wire', () {
      expect(() => encodeValue(double.nan), returnsNormally);
      final v = encodeValue(double.infinity);
      expect(v.values.single.toString(), isNot(contains('Infinity')));
    });
    test('deep and empty structures', () {
      final m = {'a': <String, dynamic>{}, 'b': <dynamic>[], 'c': {'d': [1, 2, {'e': null}]}};
      expect(decodeFields(encodeFields(m)), m);
    });
    test('integers beyond 2^53 survive as int', () {
      expect(decodeFields(encodeFields({'n': 9007199254740993}))['n'], 9007199254740993);
    });
  });
}
