import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The owner's two dogs, the black doodle and the white whippet, pacing the
/// strip beside the Home's Welcome: they walk, turn at the ends, and now and
/// then stop, the doodle to bark, the whippet to sit.
///
/// Frames are `assets/dogs/{black,white}_{stand,walk0..4,sit}.png` and
/// `black_bark.png`, cut
/// from the owner's sprite sheet, all facing right; a dog walking left is the
/// same frame mirrored. With animations off (the system setting, or a test)
/// both stand still.
class DogPark extends StatefulWidget {
  const DogPark({super.key, required this.height});

  /// The whippet's height, the taller of the two; the doodle keeps its scale.
  final double height;

  @override
  State<DogPark> createState() => _DogParkState();
}

/// Each dog's frame, in asset pixels: they share one scale.
const _assetHeight = {'black': 142.0, 'white': 146.0};
const _assetWidth = {'black': 180.0, 'white': 196.0};
const _walkFrames = 5;

enum _Pose { walk, stand, sit, bark }

class _Dog {
  _Dog(this.name, {required this.speed, required this.x, required this.right});

  final String name;

  /// Walking pace, in dog heights per second.
  final double speed;

  /// Left edge, as a share of the room the dog has to walk in (0 to 1).
  double x;
  bool right;
  _Pose pose = _Pose.walk;

  /// Seconds into the current step of [_plan].
  double clock = 0;
  double walked = 0;
  List<(_Pose, double)> plan = const [];

  String get frame => switch (pose) {
    _Pose.walk => 'walk${(walked / 0.13).floor() % _walkFrames}',
    _Pose.stand => 'stand',
    _Pose.sit => 'sit',
    _Pose.bark => 'bark',
  };
}

class _DogParkState extends State<DogPark> with SingleTickerProviderStateMixin {
  final _random = math.Random();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _width = 0;

  late final List<_Dog> _dogs = [
    _Dog('white', speed: 0.9, x: 0.15, right: true),
    _Dog('black', speed: 0.7, x: 0.75, right: false),
  ];

  static final bool _underTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    for (final dog in _dogs) {
      dog.plan = _walkFor(dog);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final dog in const ['black', 'white']) {
      for (final frame in [
        'stand',
        'sit',
        if (dog == 'black') 'bark',
        for (var i = 0; i < _walkFrames; i++) 'walk$i',
      ]) {
        precacheImage(AssetImage('assets/dogs/${dog}_$frame.png'), context);
      }
    }
    final still = _underTest || MediaQuery.disableAnimationsOf(context);
    if (still) {
      if (_ticker.isActive) _ticker.stop();
      for (final dog in _dogs) {
        dog.pose = _Pose.stand;
      }
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _between(double a, double b) => a + _random.nextDouble() * (b - a);

  /// A stretch of walking, then a stop.
  List<(_Pose, double)> _walkFor(_Dog dog) => [
    (_Pose.walk, _between(3, 7)),
    ..._stopFor(dog),
  ];

  /// What a stop is: the doodle sits and barks; the whippet never barks,
  /// and sometimes sits a while, otherwise only pauses.
  List<(_Pose, double)> _stopFor(_Dog dog) {
    if (dog.name == 'white') {
      return _random.nextDouble() < 0.45
          ? [
              (_Pose.stand, 0.4),
              (_Pose.sit, _between(1.5, 3)),
              (_Pose.stand, 0.4),
            ]
          : [(_Pose.stand, _between(0.6, 1.2))];
    }
    final barks = 2 + _random.nextInt(3);
    return [
      (_Pose.sit, 0.5),
      for (var i = 0; i < barks; i++) ...[(_Pose.bark, 0.22), (_Pose.sit, 0.3)],
      (_Pose.sit, 0.6),
    ];
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = now;
    if (dt <= 0 || dt > 0.25 || _width <= 0) return;
    for (final dog in _dogs) {
      _advance(dog, dt);
    }
    setState(() {});
  }

  void _advance(_Dog dog, double dt) {
    final (pose, length) = dog.plan.first;
    dog.pose = pose;
    dog.clock += dt;
    if (pose == _Pose.walk) {
      dog.walked += dt;
      final room = _width - _dogWidth(dog);
      if (room > 0) {
        final step = dog.speed * widget.height * dt / room;
        dog.x += dog.right ? step : -step;
        if (dog.x >= 1) {
          dog.x = 1;
          dog.right = false;
        }
        if (dog.x <= 0) {
          dog.x = 0;
          dog.right = true;
        }
      }
    }
    if (dog.clock < length) return;
    dog.clock = 0;
    dog.plan = dog.plan.sublist(1);
    if (dog.plan.isEmpty) {
      // Off again, most often the way it was going.
      if (_random.nextDouble() < 0.35) dog.right = !dog.right;
      dog.plan = _walkFor(dog);
    }
  }

  double _scale() => widget.height / _assetHeight['white']!;
  double _dogWidth(_Dog dog) => _assetWidth[dog.name]! * _scale();
  double _dogHeight(_Dog dog) => _assetHeight[dog.name]! * _scale();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, box) {
            _width = box.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final dog in _dogs)
                  Positioned(
                    left: dog.x * math.max(0, _width - _dogWidth(dog)),
                    bottom: 0,
                    child: Transform.flip(
                      flipX: !dog.right,
                      child: Image.asset(
                        'assets/dogs/${dog.name}_${dog.frame}.png',
                        width: _dogWidth(dog),
                        height: _dogHeight(dog),
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
