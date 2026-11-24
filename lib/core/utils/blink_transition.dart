import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// This fork's ("Stack") one page transition: a blink. The new page fades in
/// fast over the old one, which stays put; leaving, it fades out as fast.
/// No slide, no zoom, no turning page anywhere in the app.
abstract final class Blink {
  static const Duration inDuration = Duration(milliseconds: 160);
  static const Duration outDuration = Duration(milliseconds: 120);

  static Widget transition(Animation<double> animation, Widget child) =>
      FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
        child: child,
      );

  /// A go_router page that blinks in.
  static Page<T> page<T>({
    required LocalKey key,
    required Widget child,
    String? name,
  }) => CustomTransitionPage<T>(
    key: key,
    name: name,
    transitionDuration: inDuration,
    reverseTransitionDuration: outDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        transition(animation, child),
    child: child,
  );
}

/// The theme's transition for every [MaterialPageRoute] and [MaterialPage]:
/// the blink.
class BlinkPageTransitionsBuilder extends PageTransitionsBuilder {
  const BlinkPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Blink.inDuration;

  @override
  Duration get reverseTransitionDuration => Blink.outDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => Blink.transition(animation, child);
}

/// Every platform's page transition: the blink.
const blinkPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: BlinkPageTransitionsBuilder(),
    TargetPlatform.iOS: BlinkPageTransitionsBuilder(),
    TargetPlatform.macOS: BlinkPageTransitionsBuilder(),
    TargetPlatform.windows: BlinkPageTransitionsBuilder(),
    TargetPlatform.linux: BlinkPageTransitionsBuilder(),
    TargetPlatform.fuchsia: BlinkPageTransitionsBuilder(),
  },
);
