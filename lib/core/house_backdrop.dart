import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Whether [image] is the owner's own picture (Settings › Background)
  /// rather than the house.
  static bool custom = false;

  /// Ticks whenever the picture changes, for every painter of the room.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static const String _prefsKey = 'stack_background_path';

  /// Reads and decodes the picture once, before the first frame: the one the
  /// owner chose, when there is one and it still reads, else the house.
  static Future<void> load() async {
    if (image != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_prefsKey);
      if (path != null && File(path).existsSync()) {
        image = await _decode(await File(path).readAsBytes(), 1440);
        custom = true;
        return;
      }
    } catch (_) {
      custom = false;
    }
    await _loadHouse();
  }

  static Future<void> _loadHouse() async {
    try {
      final data = await rootBundle.load(asset);
      image = await _decode(data.buffer.asUint8List(), 1100);
    } catch (_) {
      image = null;
    }
    custom = false;
  }

  static Future<ui.Image> _decode(Uint8List bytes, int width) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    return (await codec.getNextFrame()).image;
  }

  /// Asks for a picture and makes it the background, app-wide. False when
  /// nothing was chosen; throws when the picture could not be read.
  static Future<bool> choose() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final source = picked?.files.singleOrNull?.path;
    if (source == null) return false;
    final bytes = await File(source).readAsBytes();
    final decoded = await _decode(bytes, 1440);
    // Kept in the app's own storage: the picked file may be a cache copy the
    // system clears.
    final dir = await getApplicationDocumentsDirectory();
    final dot = source.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : source.substring(dot + 1).toLowerCase();
    final kept = File('${dir.path}/background.$ext');
    await kept.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_prefsKey);
    if (old != null && old != kept.path) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    await prefs.setString(_prefsKey, kept.path);
    image = decoded;
    custom = true;
    changes.value++;
    return true;
  }

  /// Puts the house back.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_prefsKey);
    await prefs.remove(_prefsKey);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    await _loadHouse();
    changes.value++;
  }
}

/// Paints the house into [room], over its ground and under its light.
void paintHouse(Canvas canvas, Rect room, ColorScheme scheme) {
  final image = HouseBackdrop.image;
  if (image == null) return;

  final width = room.width;
  final Rect photo;
  if (HouseBackdrop.custom) {
    // The owner's own picture covers the whole room, centred.
    final scale = math.max(
      room.width / image.width,
      room.height / image.height,
    );
    final w = image.width * scale;
    final h = image.height * scale;
    photo = Rect.fromLTWH(
      room.left + (room.width - w) / 2,
      room.top + (room.height - h) / 2,
      w,
      h,
    );
  } else {
    photo = Rect.fromLTWH(
      room.left,
      room.top + HouseBackdrop.topInset - width * HouseBackdrop.lift,
      width,
      width * image.height / image.width,
    );
  }
  final height = photo.height;

  canvas.save();
  canvas.clipRect(room);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    photo,
    Paint()..filterQuality = FilterQuality.medium,
  );

  // The sky, darkened so the date and the title read over it.
  final sky = Rect.fromLTWH(photo.left, photo.top, photo.width, height * 0.34);
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
    photo.width,
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
