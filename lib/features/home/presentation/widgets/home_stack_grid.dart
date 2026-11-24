import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_panel.dart';
import 'package:cupola/features/home/presentation/widgets/home_header.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// This fork's ("Stack") Home, laid out as the Living Room Remote: the time
/// and the date over the sky, the house in the middle, and below it a grid of
/// glass tiles, one per service set up on the Stack, each with its own logo.
/// The service opened last keeps its brand colour's glow, as the remote keeps
/// the app it last opened lit.
class HomeStackGrid extends ConsumerStatefulWidget {
  const HomeStackGrid({super.key});

  @override
  ConsumerState<HomeStackGrid> createState() => _HomeStackGridState();
}

/// The service a Home tile opened last, for its glow.
final homeLastOpenedProvider = StateProvider<ServiceKey?>((ref) => null);

/// The logo each tile draws: the open-source dashboard-icons set
/// (homarr-labs/dashboard-icons), in `assets/brand/services`.
String serviceLogoAsset(ServiceKey service) =>
    'assets/brand/services/${service.name}.png';

/// Each service's brand colour, for its glow: read off its logo, and the
/// remote's own for Jellyfin.
Color serviceBrandColor(ServiceKey service) => switch (service) {
  ServiceKey.seerr => const Color(0xFF836FE6),
  ServiceKey.radarr => const Color(0xFFF5B61C),
  ServiceKey.sonarr => const Color(0xFF00B4E2),
  ServiceKey.lidarr => const Color(0xFF00D879),
  ServiceKey.bazarr => const Color(0xFFDCE4F5),
  ServiceKey.prowlarr => const Color(0xFFE55C05),
  ServiceKey.readarr => const Color(0xFFD82828),
  ServiceKey.qbittorrent => const Color(0xFF4487D8),
  ServiceKey.truenas => const Color(0xFF00A0DF),
  ServiceKey.dockge => const Color(0xFF7DC6FA),
  ServiceKey.unraid => const Color(0xFFF44C19),
  ServiceKey.jellyfin => const Color(0xFF8C63D9),
  ServiceKey.plex => const Color(0xFFE5A00D),
  ServiceKey.emby => const Color(0xFF56D84D),
};

const _text = Color(0xFFF5F7FF);
const _text2 = Color(0xFFAEB6D6);

/// The remote's face on Android: "Helvetica Neue", then Roboto.
const _face = 'StackRoboto';

class _HomeStackGridState extends ConsumerState<HomeStackGrid> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final services = [
      for (final domain in ServiceDomain.values)
        for (final service in domain.services)
          if (settings.isServiceConfigured(service)) service,
    ];
    final health = ref.watch(stackHealthProvider);
    final line = homeHealthLine(health);
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time = '$hour:${now.minute.toString().padLeft(2, '0')}';
    final date = '${weekdayName(now)}, ${monthName(now)} ${now.day}';
    final clean =
        health.configured > 0 &&
        health.headline != null &&
        health.checking == 0 &&
        line.startsWith('${health.configured} of ${health.configured}');

    final width = MediaQuery.sizeOf(context).width;
    // Measured off the Living Room Remote on the owner's phone (448dp wide):
    // every figure below is in those dp, scaled to this screen's width, and
    // drawn with no text scaling, so the two pages match to the point.
    final k = math.min(width, 460.0) / 448;
    final side = math.max(0.0, (width - 460) / 2);
    const scale = TextScaler.noScaling;
    const shadow = [
      Shadow(color: Color(0xD9000000), blurRadius: 12, offset: Offset(0, 2)),
    ];
    final timeSize = 89.7 * k;
    final dateSize = 18.0 * k;
    final stateSize = 17.0 * k;

    final gridTop = 456.1 * k;
    final tileHeight = 97.3 * k;
    final gap = 11.5 * k;
    final margin = 19.0 * k;
    final tileWidth = (math.min(width, 460.0) - 2 * margin - 2 * gap) / 3;

    final header = SizedBox(
      height: gridTop,
      child: Stack(
        children: [
          Positioned(
            left: side + 16.9 * k,
            top: 67.2 * k,
            child: Text(
              time,
              textScaler: scale,
              style: TextStyle(
                fontFamily: _face,
                fontSize: timeSize,
                fontWeight: FontWeight.w400,
                letterSpacing: -2.2 * k,
                height: 1,
                color: _text,
                shadows: const [
                  Shadow(
                    color: Color(0x59000000),
                    blurRadius: 30,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: side + 19.2 * k,
            top: 178.9 * k,
            child: Text(
              date,
              textScaler: scale,
              style: TextStyle(
                fontFamily: _face,
                fontSize: dateSize,
                height: 1,
                color: _text2,
                shadows: shadow,
              ),
            ),
          ),
          if (line.isNotEmpty)
            Positioned(
              left: side + 19.0 * k,
              top: 209.6 * k,
              child: GestureDetector(
                onTap: () => context.go(ServiceRoutes.stack),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(
                      clean: clean,
                      checking: health.checking > 0,
                      size: 8 * k,
                    ),
                    SizedBox(width: 9 * k),
                    Text(
                      line,
                      textScaler: scale,
                      style: TextStyle(
                        fontFamily: _face,
                        fontSize: stateSize,
                        height: 1,
                        color: const Color(0xE0F5F7FF),
                        shadows: shadow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Settings, where the remote keeps its round power button.
          Positioned(
            right: side + 20.0 * k,
            top: 87.5 * k,
            child: _RoundGlassButton(
              size: 55 * k,
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => openSettings(context, ref),
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: EdgeInsets.only(
        bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side + margin),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            crossAxisCount: 3,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: tileWidth / tileHeight,
            children: [
              for (final service in services)
                _Tile(
                  service: service,
                  address: _addressOf(settings.primaryOf(service)?.url ?? ''),
                  k: k,
                  onTap: () {
                    ref.read(homeLastOpenedProvider.notifier).state = service;
                    context.go(ServiceRoutes.forService(service));
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.clean, required this.checking, this.size = 8});

  final bool clean;
  final bool checking;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = checking
        ? const Color(0xFFFFD98A)
        : clean
        ? const Color(0xFF7CF0A6)
        : const Color(0xFFFFB86B);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 10)],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.service,
    required this.address,
    required this.k,
    required this.onTap,
  });

  final ServiceKey service;
  final String address;

  /// The screen's scale against the remote's 448dp.
  final double k;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final k = widget.k;
    const curve = Cubic(.22, .9, .24, 1);
    const scale = TextScaler.noScaling;
    final nameSize = 15.4 * k;
    final addressSize = 9.5 * k;
    return Semantics(
      button: true,
      label: service.title,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: const Duration(milliseconds: 220),
          curve: curve,
          // The remote's tile, measured: the logo 40 tall from 14.7 down, the
          // name's baseline 82.2 down; here the address under it, small.
          child: GlassPanel(
            radius: 22 * k,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 14.7 * k,
                  child: Icon(
                    service.icon,
                    size: 40 * k,
                    color: const Color(0xF0F5F7FF),
                  ),
                ),
                Positioned(
                  left: 6 * k,
                  right: 6 * k,
                  top: (82.2 - 0.927 * 15.8 - 1.9) * k,
                  child: Text(
                    service.shortTitle,
                    textAlign: TextAlign.center,
                    textScaler: scale,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: _face,
                      fontSize: nameSize,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xEBF5F7FF),
                      shadows: const [
                        Shadow(
                          color: Color(0x59000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.address.isNotEmpty)
                  Positioned(
                    left: 6 * k,
                    right: 6 * k,
                    top: (93.0 - 0.927 * 9.5) * k,
                    child: Text(
                      widget.address,
                      textAlign: TextAlign.center,
                      textScaler: scale,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _face,
                        fontSize: addressSize,
                        height: 1,
                        color: _text2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The remote's round glass button (its power and Santa buttons): here,
/// Settings.
class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.size,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: GlassPanel(
          radius: size / 2,
          child: Center(
            child: Icon(icon, size: size * 0.44, color: _text),
          ),
        ),
      ),
    ),
  );
}

/// `nas.home.arpa:8989`: the host and, when it has one, the port.
String _addressOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url.trim();
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}
