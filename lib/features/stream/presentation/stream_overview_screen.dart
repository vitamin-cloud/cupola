import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_provider.dart';
import 'package:cupola/features/stream/presentation/stream_watching.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// The first tab of a media server's service home: Jellyfin's and Plex's both.
///
/// **One screen, two services**, like every other surface in this folder: the
/// only per-service input is [service], and the difference between the two
/// servers lives in what their clients can answer, never in a fork of the page.
/// The two boards are genuinely not the same board, and where they differ the
/// difference is real here too: Plex draws an On deck rail and a Server region
/// that Jellyfin has no endpoint for, and neither server draws anything the
/// other one merely *might* have.
///
/// Overview alone carries the identity block and the readouts; every other tab
/// is a view of one kind of record, and then the regions in the order the
/// *mobile* boards put them, which is the order that survives the narrow width:
/// who is watching, what is half-watched, what the shelf is doing, and (Plex)
/// what the box says about itself.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// ## What the board asks for and this page does not draw
///
/// The full list, with the exact endpoint boundary for each, is in the library
/// comment of `stream_overview_provider.dart`. The short of it: no bandwidth
/// figure (neither server measures egress), no Recently added rail (no
/// server-wide recent endpoint, and `StreamItem` has no `addedAt` to sort by),
/// and no Jellyfin Continue watching (`/Users/{id}/Items/Resume` is not part
/// of the current client). Tasks, Users, Devices, Playlists and the supported
/// live-session activity views are dedicated tabs rather than duplicate
/// Overview regions. Unsupported figures remain absent rather than fabricated.
///
/// Sections load and fail independently. A server answering `/Sessions` but not
/// its library list still draws the rest, and the one that could not load says
/// so in its own slot rather than taking the page with it.
///
/// **One connection per page.** The page reads the connection the visit has in
/// view (`streamInstanceOf`: what a link opened the service on, else the lens),
/// and every region below reads it, the identity line and the figures
/// included: a page whose header names one connection and whose figures come
/// from another is the one thing it must not be.
class StreamOverviewScreen extends ConsumerWidget {
  const StreamOverviewScreen({
    super.key,
    required this.service,
    this.topPadding = _hostedTopPadding,
    this.instanceId,
  });

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Jellyfin or Plex.
  final ServiceKey service;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  /// The `?i=` of the location the page was built for. A tab's root reads
  /// the connection the visit has in view first (`streamInstanceOf`, not
  /// pinned) and this where the visit has none; null, or one that names no
  /// connection of [service], reads the lens.
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      service.isMediaServer,
      'StreamOverviewScreen only serves media servers',
    );

    // Checked **before** any provider is reached. `jellyfinClientProvider` and
    // `plexClientProvider` both throw "<service> not configured", and letting
    // `AsyncValueWidget` catch that throw would draw the same pixels while
    // leaving failed providers behind it, each scheduling a retry with backoff
    // for a condition no amount of waiting changes, which surfaces in tests as
    // a pending timer and on device as a battery cost. It matters more here
    // than elsewhere: the sessions providers deliberately carry
    // `retry: noProviderRetry` precisely because a dark media server must not
    // be hammered, and reaching them unconfigured would be the one path that
    // re-introduces what that flag exists to prevent.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(service),
      ),
    );

    return AmbientScaffold(
      accent: service.accent,
      body: SafeArea(
        bottom: false,
        child: configured
            ? _OverviewBody(
                service: service,
                topPadding: topPadding,
                instanceId: streamInstanceOf(
                  ref,
                  service,
                  instanceId,
                  pinned: false,
                ),
              )
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to this server's own connection form
            // rather than to the settings index.
            : NotConfiguredPlaceholder.forService(service),
      ),
    );
  }
}

/// The shelves the Overview glances at, in the order they are drawn.
const _glance = [
  StreamWatchingShelf.continueWatching,
  StreamWatchingShelf.recentlyAdded,
];

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.service,
    required this.topPadding,
    required this.instanceId,
  });

  final ServiceKey service;
  final double topPadding;

  /// The connection every region reads; empty is the lens.
  final String instanceId;

  /// The figures of the connection the page reads: the lens's own fold when it
  /// is the lens, and that connection's when it is another.
  ///
  /// `serviceKpiForProvider` is null only for a connection that cannot be read
  /// on its own, which neither media server is; read as no figures, which the
  /// peek draws as dashes, never as zeros.
  AsyncValue<List<ServiceKpi>> _kpisOf(WidgetRef ref) {
    if (instanceId.isEmpty) return ref.watch(serviceKpiProvider(service));
    return ref
        .watch(
          serviceKpiForProvider((service: service, instanceId: instanceId)),
        )
        .whenDataKept((kpis) => kpis ?? const <ServiceKpi>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read once here rather than inside the section: the sessions region is a
    // shared widget that takes the value, because *it* must not decide which
    // server it is talking to and must not be the thing that first reaches a
    // provider on an unconfigured service.
    final connection = (service: service, instanceId: instanceId);
    // Read again while the room is seen: its figure, Now playing and light
    // all read this one answer, so they move together.
    ref.watchWhileLive(context, streamSessionsPollProvider(connection));
    final sessions = ref.watch(streamSessionsForProvider(connection));
    final libraries = ref.watch(streamLibrariesForProvider(connection));

    void refresh() {
      invalidateServiceReadout(ref, service);
      // The connection's own reads, then the lens's: the lens's collapse onto
      // the plain providers, which hold the answer the others re-read.
      ref.invalidate(
        serviceKpiForProvider((service: service, instanceId: instanceId)),
      );
      ref.invalidate(streamSessionsForProvider(connection));
      ref.invalidate(streamLibrariesForProvider(connection));
      final backend = streamBackendOf(service);
      ref.invalidate(backend.sessions);
      ref.invalidate(backend.libraries);
      for (final shelf in _glance) {
        ref.invalidate(
          streamWatchingProvider((
            service: service,
            instanceId: instanceId,
            shelf: shelf,
          )),
        );
      }
    }

    // **One** state for a server that is dark, not one per region. Sessions
    // and the library list are the two reads both servers answer; when both
    // failed with nothing retained there is no region left to draw, and three
    // stacked error wells each saying the same thing about the same box was a
    // page shouting. The identity line and the readouts stay above it: the
    // host, and "—" where a figure had no answer.
    final serverDark =
        sessions.hasError &&
        !sessions.hasValue &&
        libraries.hasError &&
        !libraries.hasValue;

    return RefreshIndicator(
      onRefresh: () async {
        refresh();
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not four independently scrolling panes.
      child: ServiceOverviewScroll(
        topPadding: topPadding,
        children: [
          ServiceOverviewIdentity(service: service, instanceId: instanceId),
          ...sectionsOrOneLine(
            ref,
            service,
            ownSilence: true,
            instanceId: instanceId,
            [
              ServiceKpiPeek.room(kpis: _kpisOf(ref), service: service),
              if (serverDark)
                ServiceOfflineState.failure(
                  service: service,
                  instanceId: instanceId,
                  error: sessions.error!,
                  onRetry: refresh,
                )
              else ...[
                // Who is watching, first and on both servers: it is the one fact
                // only a media server holds, and the only region on this page
                // that is about people rather than about files.
                StreamNowPlayingSection.slab(
                  service: service,
                  instanceId: instanceId,
                  sessions: sessions,
                ),
                if (service.speaksMediaBrowser &&
                    ref.watch(
                      mediaBrowserProvidersOf(
                        service,
                      ).lacksAdministratorFor(instanceId),
                    ))
                  const JellyfinOwnPlaybackNote(),
                const SizedBox(height: AppSpacing.lg),
                // The glance at what is being watched (decision
                // `P-stream-library-browse`): what the viewer is partway
                // through, and what was added, each leading to Activity
                // where it is whole.
                for (final shelf in _glance)
                  StreamWatchingRail(
                    service: service,
                    instanceId: instanceId,
                    shelf: shelf,
                  ),
                _LibrariesSection(service: service, instanceId: instanceId),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Libraries ──────────────────────────────────────────────────────────────

/// The shelf: which rooms are on the server, and what is happening to them.
///
/// **A peek, not the list.** The Libraries tab one tap away draws every room as
/// a destination; this draws three of them as a readout, with the census over
/// the top. Naming them costs nothing: one `getLibraries` response already
/// answered names and kinds, and it is what keeps a page the user lands on
/// every time they open the service from being a header over a single "no scan
/// running" note, which on a home server is the majority state rather than the
/// edge case. Only the per-library item counts are refused (decision 21: one
/// request per library, and that cost belongs to the tab).
///
/// The header's census comes from the whole list and the rows are capped, so a
/// full rescan reads `9 scanning` above three rows rather than reporting three.
///
/// **An empty list is an empty shelf, and a dark server is a failure.** Both
/// clients used to swallow their own failure into `[]`, and this region leaned
/// on the reachability probe to guess which of the two it had been handed. They
/// throw now, so the failure lands in the region's own slot with a Retry and an
/// empty list is only ever the server's answer.
class _LibrariesSection extends ConsumerWidget {
  const _LibrariesSection({required this.service, required this.instanceId});

  final ServiceKey service;

  /// The connection whose shelf this is; empty is the lens.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `/Library/VirtualFolders` is elevated on Jellyfin, so a household
    // member's token is refused it: the Libraries tab says so calmly, and so
    // does this region, rather than drawing the refusal as a fault.
    if (service.librariesNeedAdministrator &&
        ref.watch(
          mediaBrowserProvidersOf(service).lacksAdministratorFor(instanceId),
        )) {
      return ServiceOverviewSection(
        service: service,
        title: 'Libraries',
        subtitle: '—',
        destination: ServiceTab.libraries,
        child: ServiceOverviewEmpty(
          icon: Icons.admin_panel_settings_outlined,
          label: needsAdministratorTitle(service),
        ),
      );
    }
    final libraries = ref.watch(
      streamLibrariesForProvider((service: service, instanceId: instanceId)),
    );
    // One `now` for the whole region, so two rows built microseconds apart
    // cannot disagree about which side of a boundary they are on.
    final now = DateTime.now();

    return ServiceOverviewSection(
      service: service,
      title: 'Libraries',
      // "—" while the list is in flight and after it failed. A "0 libraries"
      // printed over an unanswered question is a claim nobody made, and it is
      // the claim a user would act on, by going to look for libraries that are
      // there.
      subtitle:
          streamLibrariesCensus(libraries: libraries.asData?.value) ?? '—',
      destination: ServiceTab.libraries,
      child: AsyncValueWidget<List<StreamLibrary>>.section(
        value: libraries,
        service: service,
        instanceId: instanceId,
        consequence: 'its libraries are not shown',
        loadingLabel: 'Loading the libraries',
        onRetry: () {
          ref.invalidate(
            streamLibrariesForProvider((
              service: service,
              instanceId: instanceId,
            )),
          );
          ref.invalidate(streamBackendOf(service).libraries);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (list) => list.isEmpty,
        // Only a server that answered reaches this: a dark one is the error
        // branch above, never an empty list.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.video_library_outlined,
          label: 'No libraries on this server',
        ),
        data: (list) => Column(
          children: [
            for (final row in streamShelfRows(list, now: now))
              _ShelfRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.row});

  final StreamShelfRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: a scan in progress is
    // **informational**: the server is doing what it was told to do, and a
    // library at rest is neutral. Neither is a fault, and amber here would put
    // a working library in the colour of a broken import.
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Icon(row.icon, size: 18, color: tone),
      title: row.title,
      detail: row.detail,
    );
  }
}

// ─── Server (Plex only) ─────────────────────────────────────────────────────
