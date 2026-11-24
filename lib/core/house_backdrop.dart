import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The house at night: the photo from the owner's Living Room Remote, standing
/// still behind every room while the page scrolls over it.
///
/// Painted by [paintHouse], from `paintRoom` (`ambient_background.dart`), so
/// the room and every patch of it (the status-bar scrim) show the same photo
/// in the same place. The room is its own layer, so a scroll does not repaint
/// it.
///
/// Laid out as the remote lays it: the full width of the room, lifted by
/// [lift] of that width, the sky shaded at the top and the bottom faded into
/// the room's ground.
abstract final class HouseBackdrop {
  static const String asset = 'assets/backdrop/house.jpg';

  /// How far the photo sits above the top of the room, as a share of its
  /// width (the remote's `margin-top: -13%`).
  static const double lift = 0.13;

  /// The status bar's height: the remote's page starts below it, and so does
  /// its photo. Set once the app knows it (`CupolaApp`'s builder).
  static double topInset = 0;

  /// The decoded photo, or null before [load] or if it could not be read:
  /// the room is then drawn as it always was.
  static ui.Image? image;

  /// Reads and decodes the photo once, before the first frame.
  static Future<void> load() async {
    if (image != null) return;
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 1100,
      );
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      image = null;
    }
  }
}

/// Paints the house into [room], over its ground and under its light.
void paintHouse(Canvas canvas, Rect room, ColorScheme scheme) {
  final image = HouseBackdrop.image;
  if (image == null) return;

  final width = room.width;
  final height = width * image.height / image.width;
  final photo = Rect.fromLTWH(
    room.left,
    room.top + HouseBackdrop.topInset - width * HouseBackdrop.lift,
    width,
    height,
  );

  canvas.save();
  canvas.clipRect(room);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    photo,
    Paint()..filterQuality = FilterQuality.medium,
  );

  // The sky, darkened so the date and the title read over it.
  final sky = Rect.fromLTWH(photo.left, photo.top, width, height * 0.34);
  canvas.drawRect(
    sky,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x8C060914), Color(0x00060914)],
      ).createShader(sky),
  );

  // The bottom of the photo, faded into the ground below it.
  final fade = Rect.fromLTWH(
    photo.left,
    photo.top + height * 0.58,
    width,
    height * 0.42 + 1,
  );
  canvas.drawRect(
    fade,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          scheme.surface.withValues(alpha: 0),
          scheme.surface.withValues(alpha: 0.7),
          scheme.surface,
        ],
        stops: const [0, 0.45, 1],
      ).createShader(fade),
  );
  canvas.restore();
}
