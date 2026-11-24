import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/glass_panel.dart';
import 'package:cupola/core/widgets/library_selection.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_bar_action.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The root page of one of a service's tabs: the bar, and the tab's own content
/// under it.
///
/// **The bar is drawn here and not by the shell.** That is what lets a pushed
/// page (a film, a wizard, a search result) hide it without leaving the branch
/// it was pushed from: the page is pushed on *this* branch's navigator and
/// simply covers this widget. A bar owned by the shell would sit above every
/// branch navigator and could not be covered by anything inside one, so hiding
/// it would mean unmounting the thing that holds the stack you want to come back
/// to.
///
/// The band is glass for the same reason the service app bar above it is: the
/// hosted screen's ambient gradient has to read continuously behind both, and a
/// scrolling list has to frost under them rather than stop at a hard edge.
///
/// On a desktop window there is no band above it: the bar is drawn as
/// [ServiceTabBar.header] and is the service's whole header, flush with the
/// deck. See [ServiceHomeScreen.drawsBand]. That header is not glass: it is
/// the room's one lit surface, opaque so its ink can be measured.
class ServiceTabScaffold extends StatelessWidget {
  final ServiceKey service;
  final ServiceTab tab;
  final Widget child;

  const ServiceTabScaffold({
    super.key,
    required this.service,
    required this.tab,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // TrueNAS keeps its console, so it has no bar to draw and no branch to
    // switch. Nothing is drawn rather than an empty strip.
    if (tabsFor(service) == null) return child;

    if (!ServiceHomeScreen.drawsBand(context, service)) {
      final action = serviceBarAction(service);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Every hosted screen reserves the phone's band and bar at its top:
          // the router hands it one constant when the route is built, and the
          // route is not rebuilt when a resize moves the window across
          // [AppBreakpoints.desktopMobile]. So the screen keeps that layout and
          // is lifted by the band this window does not draw: its reserved band
          // falls above the edge instead of standing as a 56pt gap. Decided
          // here, per build, because only here is there a context to ask.
          Positioned(
            top: -kToolbarHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: child,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // Not glass: the header paints its own opaque band lit by the lamp,
            // so a frost behind it would be covered.
            child: ServiceTabBar.header(
              service: service,
              current: tab,
              onSelected: (next) => _go(context, next),
              lens: InstanceLensBadge(service: service),
              actions: [?action],
            ),
          ),
        ],
      );
    }

    // This fork: the page ends a hair (2pt) below the tabs' slab, so nothing
    // scrolls under it or the band: it is gone before it reaches them. Not
    // while a library selects: its selection header stands in their place.
    final selecting = LibrarySelectionScope.selectingOf(context);
    final top =
        ServiceHomeScreen.bandHeightOf(context) + ServiceTabBar.height + 2;
    return Stack(
      children: [
        if (selecting) child else ClipRect(clipper: _Below(top), child: child),
        Positioned(
          // The band's full height, inset included, not `kToolbarHeight`.
          // The band consumes the top inset (`Positioned(top: 0)` under a
          // `SafeArea`), so on every notched phone it reaches an inset lower
          // than the constant, and a bar placed at the bare constant would be
          // overlapped by exactly that much.
          top: ServiceHomeScreen.bandHeightOf(context),
          left: 0,
          right: 0,
          // Steps aside with the band while a library selects: a tab cannot
          // be switched from under a selection.
          child: LibrarySelectionHide(
            child: SafeArea(
              bottom: false,
              // The band above already consumed the top inset, and this widget
              // has now been offset past it: consuming it a second time here
              // would push the bar a status bar below where the content
              // reserves it.
              top: false,
              // This fork: the tabs ride a frosted slab, like the Overview's
              // cards, instead of a strip of the room painted over the page.
              // The room (and the house photo) stays behind everything.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: FrostedTabSlab(
                  child: ServiceTabBar(
                    service: service,
                    current: tab,
                    onSelected: (next) => _go(context, next),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _go(BuildContext context, ServiceTab next) {
    final tabs = tabsFor(service);
    if (tabs == null) return;
    final index = tabs.indexOf(next);
    if (index < 0) return;

    // `goBranch`, not `context.go`. It restores the target branch's own stack,
    // which is the whole of "back returns to the tab you left, scrolled where
    // you left it"; a plain `go` would rebuild that branch at its root and
    // throw away where the user was.
    //
    // `StatefulNavigationShell.of` walks up for the nearest shell state, so
    // from inside one of a service's tabs it finds that *service's* shell and
    // not the app's four-branch one.
    StatefulNavigationShell.of(context).goBranch(index);
  }
}

/// Clips a page to what lies [top] points below its top.
class _Below extends CustomClipper<Rect> {
  const _Below(this.top);

  final double top;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, top.clamp(0, size.height), size.width, size.height);

  @override
  bool shouldReclip(_Below old) => old.top != top;
}

/// The slab under a service's tabs: the same glass as every card
/// (`GlassPanel`). The page is clipped below it, so only the room shows
/// through, never a row.
class FrostedTabSlab extends StatelessWidget {
  const FrostedTabSlab({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GlassPanel(radius: ServiceTabBar.height / 2, child: child);
}
