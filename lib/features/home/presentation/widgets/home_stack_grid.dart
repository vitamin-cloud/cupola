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
import 'package:cupola/features/media/presentation/media_parts.dart';
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
const _face = 'Roboto';

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

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final top = media.padding.top;
    const shadow = [
      Shadow(color: Color(0xD9000000), blurRadius: 12, offset: Offset(0, 2)),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final w = math.min(box.maxWidth, 460.0);
        // Where the remote's apps start: on the faded lower part of the photo.
        final gridTop = math.max(top + 190, w * 1.02);
        final tileHeight = (w * 0.22).clamp(80.0, 96.0) + 14;
        final logo = (w * 0.09).clamp(30.0, 40.0);
        return ListView(
          padding: EdgeInsets.only(
            bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            SizedBox(
              height: gridTop,
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, top + 18, 18, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Transform.translate(
                              offset: const Offset(-3, 0),
                              child: Text(
                                time,
                                style: const TextStyle(
                                  fontFamily: _face,
                                  fontSize: 74,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -1.8,
                                  height: 1,
                                  color: _text,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x59000000),
                                      blurRadius: 30,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              date,
                              style: const TextStyle(
                                fontSize: 15,
                                color: _text2,
                                shadows: shadow,
                              ),
                            ),
                            if (line.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => context.go(ServiceRoutes.stack),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Dot(
                                      clean: clean,
                                      checking: health.checking > 0,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        line,
                                        style: const TextStyle(
                                          fontFamily: _face,
                                          fontSize: 14,
                                          color: Color(0xE0F5F7FF),
                                          shadows: shadow,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Settings, as the Stack page opens it.
                      Tooltip(
                        message: 'Settings',
                        child: MediaPlate(
                          label: 'Settings',
                          icon: Icons.settings_outlined,
                          onTap: () => openSettings(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: math.max(18, (width - 460) / 2 + 18),
              ),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: ((w - 36 - 20) / 3) / tileHeight,
                children: [
                  for (final service in services)
                    _Tile(
                      service: service,
                      address: _addressOf(
                        settings.primaryOf(service)?.url ?? '',
                      ),
                      logo: logo,
                      onTap: () {
                        ref.read(homeLastOpenedProvider.notifier).state =
                            service;
                        context.go(ServiceRoutes.forService(service));
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.clean, required this.checking});

  final bool clean;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final color = checking
        ? const Color(0xFFFFD98A)
        : clean
        ? const Color(0xFF7CF0A6)
        : const Color(0xFFFFB86B);
    return Container(
      width: 8,
      height: 8,
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
    required this.logo,
    required this.onTap,
  });

  final ServiceKey service;
  final String address;
  final double logo;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    const curve = Cubic(.22, .9, .24, 1);
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
          // The remote's tile: glass, a white mark, the name, and here the
          // address it is reached at, small, under it.
          child: GlassPanel(
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 13, 6, 9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    service.icon,
                    size: widget.logo,
                    color: const Color(0xF0F5F7FF),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        service.shortTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: _face,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xEBF5F7FF),
                          shadows: [
                            Shadow(
                              color: Color(0x59000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      if (widget.address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _face,
                            fontSize: 10,
                            color: _text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `nas.home.arpa:8989`: the host and, when it has one, the port.
String _addressOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url.trim();
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}
