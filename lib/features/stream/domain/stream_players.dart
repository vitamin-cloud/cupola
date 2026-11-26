import 'package:flutter/foundation.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// What opens a media server's title for the viewer: the server's own web
/// client, or one of the apps that take a link to an item.
///
/// Pure: the links are built here, and whether an app is installed is asked of
/// the platform by the presentation layer. Every player belongs to **one**
/// server ([service]): Swiftfin cannot open an Emby item, and offering it
/// there would be a promise the app cannot keep. Plex keeps its browser link
/// (`streamItemWebUrl`) and has no player here.
///
/// There is no Infuse. For an Emby item it would want a stream URL with the
/// API key in its query, which would leave Cupola for another app; one fewer
/// promise is better than giving the key away.
enum StreamPlayer {
  web('Jellyfin in the browser', 'In your browser'),
  swiftfin('Swiftfin', 'Opens its page'),
  streamyfin('Streamyfin', 'Plays from where you stopped'),
  fladder('Fladder', 'Opens its page');

  const StreamPlayer(this.label, this.line);

  /// The players that belong to [service], the browser last: the order the
  /// sheet draws them in. Empty for a server with no choice to make.
  static List<StreamPlayer> of(ServiceKey service) => switch (service) {
    ServiceKey.jellyfin => const [swiftfin, streamyfin, fladder, web],
    _ => const [],
  };

  /// The server this player opens titles of.
  ServiceKey get service => switch (this) {
    StreamPlayer.web ||
    StreamPlayer.swiftfin ||
    StreamPlayer.streamyfin ||
    StreamPlayer.fladder => ServiceKey.jellyfin,
  };

  /// Whether this is a server's own web client rather than an app.
  bool get isBrowser => this == StreamPlayer.web;

  /// Its name, in the sheet and in Settings.
  final String label;

  /// What it does, under its name.
  final String line;

  /// The platforms the app exists on. The browser is on every one.
  Set<TargetPlatform> get platforms => switch (this) {
    StreamPlayer.web => TargetPlatform.values.toSet(),
    StreamPlayer.swiftfin => const {TargetPlatform.iOS},
    StreamPlayer.streamyfin ||
    StreamPlayer.fladder => const {TargetPlatform.iOS, TargetPlatform.android},
  };

  /// The scheme the app claims, or null for the browser.
  String? get scheme => switch (this) {
    StreamPlayer.web => null,
    StreamPlayer.swiftfin => 'swiftfin',
    StreamPlayer.streamyfin => 'streamyfin',
    StreamPlayer.fladder => 'fladder',
  };

  /// What to ask the platform about, to learn whether the app is installed:
  /// its scheme with nothing after it. Null for the browser, which is always
  /// there.
  Uri? get probe {
    final scheme = this.scheme;
    return scheme == null ? null : Uri.parse('$scheme://');
  }

  /// The link that opens [itemId] in this app, or null when the app needs
  /// something it was not given.
  ///
  /// Swiftfin addresses an item by the server's id and the viewer's id, so
  /// without both it is not offered. Emby's app addresses it by the server's
  /// id and the item's, spelled differently on each platform ([platform],
  /// the one this runs on unless a test says otherwise): without the server
  /// id it is not offered. The browser opens [webUrl], the link
  /// `streamItemWebUrl` builds.
  Uri? link({
    required String itemId,
    String? serverId,
    String? userId,
    Uri? webUrl,
    TargetPlatform? platform,
  }) => switch (this) {
    StreamPlayer.web => webUrl,
    StreamPlayer.swiftfin =>
      serverId == null || serverId.isEmpty || userId == null || userId.isEmpty
          ? null
          : Uri.tryParse(
              'swiftfin://${Uri.encodeComponent(serverId)}'
              '/${Uri.encodeComponent(userId)}'
              '/item/${Uri.encodeComponent(itemId)}',
            ),
    StreamPlayer.streamyfin => Uri.tryParse(
      'streamyfin://topshelf/play?id=${Uri.encodeQueryComponent(itemId)}',
    ),
    StreamPlayer.fladder => Uri.tryParse(
      'fladder:///details?id=${Uri.encodeQueryComponent(itemId)}',
    ),
  };
}
