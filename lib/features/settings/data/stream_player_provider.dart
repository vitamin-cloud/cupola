import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

/// The app the viewer chose to play a Jellyfin title in, kept on this device.
/// Null means ask every time: nothing is preferred by default.
final streamPlayerChoiceProvider =
    NotifierProvider<StreamPlayerChoiceNotifier, StreamPlayer?>(
      StreamPlayerChoiceNotifier.new,
    );

/// The choice provider of [service]'s players. Throws for a server with no
/// choice to make: a caller that asks has been handed the wrong key.
NotifierProvider<StreamPlayerChoiceNotifier, StreamPlayer?>
streamPlayerChoiceOf(ServiceKey service) => switch (service) {
  ServiceKey.jellyfin => streamPlayerChoiceProvider,
  _ => throw ArgumentError.value(service, 'service', 'has no player choice'),
};

class StreamPlayerChoiceNotifier extends Notifier<StreamPlayer?> {
  StreamPlayerChoiceNotifier({String key = 'stream_player'}) : _key = key;

  final String _key;

  @override
  StreamPlayer? build() {
    // Guarded like the other preferences: a test or a screen built without
    // the preferences still draws, asking every time.
    try {
      final stored = ref.watch(sharedPreferencesProvider).getString(_key);
      return StreamPlayer.values.asNameMap()[stored];
    } catch (_) {
      return null;
    }
  }

  /// Remembers [player], or forgets the choice when it is null.
  void set(StreamPlayer? player) {
    state = player;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (player == null) {
        prefs.remove(_key);
      } else {
        prefs.setString(_key, player.name);
      }
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}
