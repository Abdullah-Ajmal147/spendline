/// One row in the "Expenses" tab:
/// ID | Date | Time | Type | Category | Person | Description | Amount | Note
/// Stored on the phone first; `pending` means not yet written to the Google Sheet.
enum EntryType {
  expense('Expense'),
  given('Given'),
  received('Received'),
  income('Income');

  const EntryType(this.label);
  final String label;

  static EntryType fromLabel(Object? s) {
    for (final t in EntryType.values) {
      if (t.label == s) return t;
    }
    return EntryType.expense;
  }

  /// Short verb shown on the type pill.
  String get verb => switch (this) {
        EntryType.expense => 'Spent',
        EntryType.given => 'Gave',
        EntryType.received => 'Got back',
        EntryType.income => 'Income',
      };

  bool get isMoneyIn => this == EntryType.received || this == EntryType.income;
}

class Entry {
  const Entry({
    required this.id,
    required this.date,
    required this.time,
    required this.type,
    required this.category,
    required this.person,
    required this.description,
    required this.amount,
    this.note = '',
    this.pending = false,
  });

  final String id;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final EntryType type;
  final String category;
  final String person;
  final String description;
  final double amount;
  final String note; // the sentence the user typed
  final bool pending; // saved on the phone, not yet in the sheet

  String get sortKey => '$date $time';

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: '${j['id'] ?? ''}',
        date: '${j['date'] ?? ''}',
        time: '${j['time'] ?? ''}',
        type: EntryType.fromLabel(j['type']),
        category: '${j['category'] ?? 'Other'}',
        person: '${j['person'] ?? ''}',
        description: '${j['description'] ?? ''}',
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0.0,
        note: '${j['note'] ?? ''}',
        pending: j['pending'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'time': time,
        'type': type.label,
        'category': category,
        'person': person,
        'description': description,
        'amount': amount,
        'note': note,
        'pending': pending,
      };

  Entry copyWith({
    String? id,
    String? date,
    EntryType? type,
    String? category,
    String? person,
    String? description,
    double? amount,
    bool? pending,
  }) =>
      Entry(
        id: id ?? this.id,
        date: date ?? this.date,
        time: time,
        type: type ?? this.type,
        category: category ?? this.category,
        person: person ?? this.person,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        note: note,
        pending: pending ?? this.pending,
      );
}
