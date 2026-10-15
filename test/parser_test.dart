import 'package:flutter_test/flutter_test.dart';
import 'package:spendline/models/entry.dart';
import 'package:spendline/services/parser.dart';

/// (input, type, amount, person, category, description, daysAgo)
const cases = <(String, EntryType, double, String, String, String, int)>[
  ('Give to rizwan 1000', EntryType.given, 1000, 'Rizwan', 'Lending', 'To Rizwan', 0),
  ('pay for lunch 500', EntryType.expense, 500, '', 'Food', 'Lunch', 0),
  ('Uber 350 yesterday', EntryType.expense, 350, '', 'Transport', 'Uber', 1),
  ('gave ali 2k for petrol', EntryType.given, 2000, 'Ali', 'Lending', 'To Ali · petrol', 0),
  ('received 500 from rizwan', EntryType.received, 500, 'Rizwan', 'Lending', 'From Rizwan', 0),
  ('Received 2k from Ali', EntryType.received, 2000, 'Ali', 'Lending', 'From Ali', 0),
  ('rizwan returned 500', EntryType.received, 500, 'Rizwan', 'Lending', 'From Rizwan', 0),
  ('salary 85000', EntryType.income, 85000, '', 'Income', 'Salary', 0),
  ('Electricity bill 3,200', EntryType.expense, 3200, '', 'Bills', 'Electricity bill', 0),
  ('rizwan ko 1000 diye', EntryType.given, 1000, 'Rizwan', 'Lending', 'To Rizwan', 0),
  ('ali se 500 liye', EntryType.received, 500, 'Ali', 'Lending', 'From Ali', 0),
  ('chai 120', EntryType.expense, 120, '', 'Food', 'Chai', 0),
  ('1.5k groceries', EntryType.expense, 1500, '', 'Food', 'Groceries', 0),
  ('lunch ke liye 400', EntryType.expense, 400, '', 'Food', 'Lunch', 0),
  ('lent Rs 750 to Hamza', EntryType.given, 750, 'Hamza', 'Lending', 'To Hamza', 0),
  ('spent 1200 on clothes at mall', EntryType.expense, 1200, '', 'Shopping', 'Clothes mall', 0),
  ('paid rent 45000', EntryType.expense, 45000, '', 'Housing', 'Rent', 0),
  ('bought medicine 860', EntryType.expense, 860, '', 'Health', 'Medicine', 0),
  ('ahmed gave me 1000', EntryType.received, 1000, 'Ahmed', 'Lending', 'From Ahmed', 0),
  // Roman Urdu / spelling variants
  ('i pay for lunch to abdullah 500', EntryType.expense, 500, 'Abdullah', 'Food', 'Lunch · Abdullah', 0),
  ('mainy 500 rizwan ko dy ha', EntryType.given, 500, 'Rizwan', 'Lending', 'To Rizwan', 0),
  ('maine rizwan ko 2 hazar diye', EntryType.given, 2000, 'Rizwan', 'Lending', 'To Rizwan', 0),
  ('rizwan ne mujhe 700 diye', EntryType.received, 700, 'Rizwan', 'Lending', 'From Rizwan', 0),
  ('mujhe ali se 300 mile', EntryType.received, 300, 'Ali', 'Lending', 'From Ali', 0),
  ('paanch sau chai ke liye', EntryType.expense, 500, '', 'Food', 'Chai', 0),
  ('ali ko dedh hazar bheja', EntryType.given, 1500, 'Ali', 'Lending', 'To Ali', 0),
  ('ali ko 500 wapas kiye', EntryType.given, 500, 'Ali', 'Lending', 'To Ali · kiye', 0),
  ('رضوان کو ۵۰۰ دیے', EntryType.given, 500, 'رضوان', 'Lending', 'To رضوان', 0),
];

void main() {
  final now = DateTime(2026, 10, 15, 14, 30);

  for (final c in cases) {
    test(c.$1, () {
      final d = parseEntry(c.$1, now: now);
      expect(d.type, c.$2, reason: 'type');
      expect(d.amount, c.$3, reason: 'amount');
      expect(d.person, c.$4, reason: 'person');
      expect(d.category, c.$5, reason: 'category');
      expect(d.description, c.$6, reason: 'description');
      expect(d.date, isoDate(DateTime(2026, 10, 15 - c.$7)), reason: 'date');
      expect(d.confidence, greaterThanOrEqualTo(.8), reason: 'confidence');
    });
  }

  test('unclear line is flagged as a guess', () {
    final d = parseEntry('something random 300', now: now);
    expect(d.amount, 300);
    expect(d.category, 'Other');
    expect(d.confidence, lessThan(.8));
  });

  group('dates', () {
    String dateOf(String t) => parseEntry(t, now: now).date; // now = Thu 15 Oct 2026
    test('kal / parson / days ago', () {
      expect(dateOf('chai 100 kal'), '2026-10-14');
      expect(dateOf('chai 100 parson'), '2026-10-13');
      expect(dateOf('chai 100 3 din pehle'), '2026-10-12');
      expect(dateOf('chai 100 2 days ago'), '2026-10-13');
      expect(dateOf('chai 100 pichle hafte'), '2026-10-08');
    });
    test('calendar dates do not leak into the amount', () {
      final d = parseEntry('lunch 80 on 5 oct', now: now);
      expect(d.date, '2026-10-05');
      expect(d.amount, 80);
      expect(parseEntry('5th october lunch 500', now: now).amount, 500);
      expect(parseEntry('oct 3 uber 350', now: now).date, '2026-10-03');
      expect(parseEntry('petrol 2000 05/10', now: now).date, '2026-10-05');
      expect(parseEntry('petrol 2000 05-10-2025', now: now).date, '2025-10-05');
    });
    test('a future month/day means last year', () {
      expect(dateOf('gift 1000 25 dec'), '2025-12-25');
    });
    test('weekday names point to the last such day', () {
      expect(dateOf('lunch 300 monday'), '2026-10-12');
      expect(dateOf('lunch 300 thursday'), '2026-10-08'); // today is Thursday
    });
    test('urdu script day and numbers', () {
      final d = parseEntry('رضوان کو پانچ سو دیے کل', now: now);
      expect(d.amount, 500);
      expect(d.date, '2026-10-14');
      expect(d.type, EntryType.given);
    });
  });

  group('learned from the user', () {
    tearDown(() {
      learnedCategories = {};
      knownPeople = {};
    });

    test('a taught word overrides the built-in category', () {
      expect(parseEntry('chai 120', now: now).category, 'Food');
      learnedCategories = {'chai': 'Entertainment'};
      expect(parseEntry('chai 120', now: now).category, 'Entertainment');
    });

    test('a full name used before is recognised', () {
      knownPeople = {'rizwan ahmed': 'Rizwan Ahmed'};
      final d = parseEntry('rizwan ahmed ko 500 diye', now: now);
      expect(d.person, 'Rizwan Ahmed');
      expect(d.description, 'To Rizwan Ahmed');
      expect(d.type, EntryType.given);
    });
  });

  test('several entries in one message', () {
    final l = parseMany('lunch 500, chai 120 aur gave ali 2000', now: now);
    expect(l.map((d) => d.amount), [500, 120, 2000]);
    expect(l[2].type, EntryType.given);
    expect(parseMany('Electricity bill 3,200', now: now).length, 1);
  });

  test('no amount means nothing to save', () {
    expect(parseEntry('netflix', now: now).amount, 0);
  });
}
