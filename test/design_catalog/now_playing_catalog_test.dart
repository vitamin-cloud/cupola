@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_slab.dart';

import 'catalog.dart';

/// Each catalog picture's light, read as the app reads it: see
/// `media_page_catalog_test.dart`.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.backdrop, 'backdrop'),
    (CatalogArt.poster, 'poster'),
  ]) {
    final bytes = io.File(
      'design/system/assets/Imagery/$file.jpg',
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: titleLightDecodeSize,
      targetHeight: titleLightDecodeSize,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData())!;
    _lights[url] = await titleLightFromPixels([
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        0xFF000000 |
            rgba.getUint8(i) << 16 |
            rgba.getUint8(i + 1) << 8 |
            rgba.getUint8(i + 2),
    ]);
  }
}

StreamSession _session({
  required String user,
  required String title,
  required String device,
  StreamPlayMethod method = StreamPlayMethod.directPlay,
  List<String> reasons = const [],
  double progress = 0.4,
  Duration remaining = const Duration(minutes: 9),
  bool paused = false,
}) => StreamSession(
  id: title,
  userName: user,
  title: title,
  subtitle: null,
  deviceLabel: device,
  posterPath: null,
  playMethod: method,
  transcodeReasons: reasons,
  bitrate: null,
  bitrateIsNominal: true,
  progress: progress,
  isPaused: paused,
  remaining: remaining,
);

void _noop() {}

/// One playback, as a Jellyfin room draws it: large, with every control.
Widget _one(BuildContext context) => ServiceOverviewSection(
  service: ServiceKey.jellyfin,
  title: 'Now playing',
  destination: ServiceTab.activity,
  light: _lights[CatalogArt.backdrop]?.art,
  child: StreamSessionFeature(
    session: _session(user: 'Anna', title: 'Sintel', device: 'Living room TV'),
    picture: (url: CatalogArt.backdrop, headers: null),
    onTogglePause: _noop,
    onMessage: _noop,
    onStop: _noop,
  ),
);

void main() {
  setUpAll(_readLights);

  catalogCard(
    'NowPlaying',
    width: 860,
    scenes: [
      CatalogScene(
        'StreamNowPlayingSection.slab · one playback · the picture across '
        'the slab, who and what, the screen and how it plays, the bar and '
        'what is left, the controls Jellyfin allows; lit by the title',
        _one,
        width: 390,
      ),
      CatalogScene(
        'StreamNowPlayingSection.slab · one playback at 200%',
        _one,
        width: 390,
        textScale: 2,
      ),
    ],
  );
}
