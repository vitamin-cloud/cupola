import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/service_mark_tile.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// This fork's ("Stack") page for adding something new to an \*arr: a field
/// that opens with the keyboard up and asks the service as you type, and
/// nothing of the library. The library's own search finds only what is
/// already there; the band's magnifying glass opens this.
///
/// [results] draws the service's lookup for a query (the rows that add a
/// title), and [queryProvider] is the one that lookup reads.
class ArrAddScaffold extends ConsumerStatefulWidget {
  const ArrAddScaffold({
    super.key,
    required this.service,
    required this.title,
    required this.hint,
    required this.queryProvider,
    required this.results,
    this.initialQuery,
  });

  final ServiceKey service;

  /// The page's heading: `Add a series`.
  final String title;

  /// The field's placeholder.
  final String hint;

  final StateProvider<String> queryProvider;
  final Widget Function(BuildContext context, String query) results;

  /// Words to start with: the library's "ask the service" row carries them.
  final String? initialQuery;

  @override
  ConsumerState<ArrAddScaffold> createState() => _ArrAddScaffoldState();
}

class _ArrAddScaffoldState extends ConsumerState<ArrAddScaffold> {
  late String _query = widget.initialQuery?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    // The lookup reads the shared query: start it on these words (or none),
    // never on what the library's field held last.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(widget.queryProvider.notifier).state = _query;
    });
  }

  void _changed(String query) {
    final trimmed = query.trim();
    if (trimmed == _query) return;
    setState(() => _query = trimmed);
    ref.read(widget.queryProvider.notifier).state = trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final theme = Theme.of(context);
    return AmbientBackground(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: kToolbarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Tooltip(
                        message: 'Back',
                        child: MediaPlate(
                          label: 'Back',
                          icon: Icons.chevron_left_rounded,
                          iconSize: 26,
                          onTap: () => RouteUtils.popOrGo(
                            context,
                            ServiceRoutes.forService(widget.service),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      ServiceMarkTile(icon: widget.service.icon, size: 36),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            widget.title,
                            style: AppType.feature.copyWith(color: room.ink),
                            textScaler: TextScaleMetrics.clampedScalerOf(
                              context,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SearchBarHeader(
                autofocus: true,
                hintText: widget.hint,
                label: widget.title,
                initialQuery: widget.initialQuery,
                onQueryChanged: _changed,
              ),
              Expanded(
                child: _query.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'Type a name to search ${widget.service.title}.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                      )
                    : widget.results(context, _query),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
