import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ignore: implementation_imports

/// [GoRouter.refreshListenable]: asks the router to evaluate its redirect
/// again without recreating it.
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref);

  /// Asks the router to evaluate its redirect again, for a change it cannot
  /// see from here (who the shell is drawn for).
  void refresh() => notifyListeners();
}

/// Keeps [RouterRefreshNotifier] alive for the lifetime of [routerProvider].
final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});
