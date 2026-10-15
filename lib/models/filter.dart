import 'entry.dart';

/// What the chat thread is narrowed to. An empty filter shows everything.
class EntryFilter {
  const EntryFilter({
    this.types = const {},
    this.category,
    this.person,
    this.from,
    this.to,
    this.query = '',
  });

  final Set<EntryType> types;
  final String? category;
  final String? person;
  final String? from; // yyyy-MM-dd, inclusive
  final String? to;
  final String query;

  static const none = EntryFilter();

  bool get active =>
      types.isNotEmpty || category != null || person != null || from != null || to != null || query.trim().isNotEmpty;

  bool matches(Entry e) {
    if (types.isNotEmpty && !types.contains(e.type)) return false;
    if (category != null && e.category != category) return false;
    if (person != null && e.person.toLowerCase() != person!.toLowerCase()) return false;
    if (from != null && e.date.compareTo(from!) < 0) return false;
    if (to != null && e.date.compareTo(to!) > 0) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${e.description} ${e.person} ${e.category} ${e.note} ${e.amount}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  EntryFilter copyWith({
    Set<EntryType>? types,
    Object? category = _keep,
    Object? person = _keep,
    Object? from = _keep,
    Object? to = _keep,
    String? query,
  }) =>
      EntryFilter(
        types: types ?? this.types,
        category: identical(category, _keep) ? this.category : category as String?,
        person: identical(person, _keep) ? this.person : person as String?,
        from: identical(from, _keep) ? this.from : from as String?,
        to: identical(to, _keep) ? this.to : to as String?,
        query: query ?? this.query,
      );
}

const Object _keep = Object();
