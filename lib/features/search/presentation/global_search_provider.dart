import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

/// Bumped to rebuild the search field from [globalSearchQueryProvider]: the
/// field reads the query once, when it is built, so a query set from outside
/// it (a recent query, the command deck) reaches it only through this.
final globalSearchFieldVersionProvider = StateProvider<int>((ref) => 0);

/// Puts [query] in the global search's field and runs it, as tapping a
/// recent query does. The command deck offers it for a word that names
/// nothing it can open (`Search everything for "…"`).
void searchEverythingFor(WidgetRef ref, String query) {
  ref.read(globalSearchQueryProvider.notifier).state = query;
  ref.read(globalSearchFieldVersionProvider.notifier).state++;
}
