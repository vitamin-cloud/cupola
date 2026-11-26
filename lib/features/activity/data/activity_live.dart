/// What Activity reads again while it is on screen, and what a pull drops.
///
/// One poll for the page, whichever view is open: the queues, the clients
/// and who is watching every [activityLiveInterval] on the views that show
/// them, the requests every [activityRequestsInterval]. History is read on
/// open, on pull and on return: a week does not change by the second.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// How often the downloads and who is watching are read again.
const activityLiveInterval = Duration(seconds: 15);

/// The poll of [tab], for the page to watch while it is the page on screen
/// (`watchWhileLive`). History has none.
final activityLivePollProvider = Provider.autoDispose.family<void, ActivityTab>(
  (ref, tab) {
    if (tab == ActivityTab.downloads) {
      ref.gatedPoll(
        id: 'activity.live',
        interval: activityLiveInterval,
        // As the Home's: a queue still being read is left to answer.
        onTick: () {
          ref.readAgainUnlessInFlight([
            ...homeDownloadsSources,
            dashboardDecisionSourceProvider(DecisionSource.queue),
          ]);
        },
      );
    }
  },
);

/// What the desktop sidebar's "In flight" reads again while it is on screen,
/// to watch with `watchWhileLive`.
///
/// The same sources as the Home's Downloads, on the Home's clock: the glance
/// is that module folded to two lines, and it must not disagree with it, nor
/// go stale on a window that never visits the Home.
final sidebarInFlightPollProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'sidebar.inflight',
    interval: homeLiveInterval,
    onTick: () => ref.readAgainUnlessInFlight(homeDownloadsSources),
  );
});

/// Drops what [tab] draws, so it is read again: a pull, a second tap on the
/// tab, a return after a while.
void invalidateActivity(WidgetRef ref, ActivityTab tab) {
  switch (tab) {
    case ActivityTab.downloads:
      for (final source in homeDownloadsSources) {
        ref.invalidate(source);
      }
      ref.invalidate(servicesArrivalsProvider);
      ref.invalidate(servicesArrHistoryProvider);
      ref.invalidate(releaseSearchJobsProvider);
      // Needs you sits at the head of Downloads: the notes of the downloads
      // acted on give way to the queue's, and every fault is read again.
      ref.read(actedFaultsProvider.notifier).clear();
      ref.invalidate(dashboardDecisionSourceProvider);
      for (final service in ServiceKey.values) {
        for (final source in dashboardSourcesOf(service)) {
          ref.invalidate(source);
        }
      }
    case ActivityTab.history:
      ref.invalidate(servicesArrivalsProvider);
      ref.invalidate(servicesFailuresSinceProvider);
  }
}

/// [invalidateActivity], then the spinner held until what [tab] draws has
/// come back. Failures are swallowed: each section paints its own.
Future<void> refreshActivity(WidgetRef ref, ActivityTab tab) async {
  invalidateActivity(ref, tab);
  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    if (tab == ActivityTab.downloads) ...[
      settle(ref.read(servicesQueueProvider.future)),
      for (final source in DecisionSource.values)
        settle(ref.read(dashboardDecisionSourceProvider(source).future)),
    ],
    if (tab == ActivityTab.history) ...[
      settle(ref.read(servicesArrivalsProvider.future)),
      settle(ref.read(servicesFailuresSinceProvider.future)),
    ],
  ]);
}
