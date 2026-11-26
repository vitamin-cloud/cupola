import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/outside/presentation/settings_notifications_screen.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/presentation/widgets/test_all_connections_button.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/presentation/widgets/settings_home_row.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_app_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/requester_settings_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_signature.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_summary_cards.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/demo/presentation/demo_settings_card.dart';

export 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart'
    show SettingsSectionLabel;

/// `/settings`, which is two things at one address.
///
/// On a window wide enough for the rail it is the **summary pane**: six cards,
/// one per area, each the door to its own page and each printing only what is
/// wrong there. It is the only row on that rail that is a readout rather than a
/// form, which is why it is called Overview.
///
/// Below that width there is no rail to be the index, so this route *is* the
/// index: the same connections card at the top, the one thing that can be
/// wrong rather than merely set, and under it the doors, grouped. One route,
/// one URL, a deep link that resolves the same on both.
class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // The page's name opens the list, and carries the space above itself.
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    );

    // The tab Settings was opened from, and the way back to it: the page is a
    // branch root with nothing to pop. Not in the desktop window, where
    // Settings is an item of the rail and the rail is the way back.
    final from = AppBreakpoints.isDesktopShell(context)
        ? null
        : ref.watch(settingsReturnProvider);
    void goBack() {
      ref.read(settingsReturnProvider.notifier).set(null);
      StatefulNavigationShell.maybeOf(context)?.goBranch(from!.index);
    }

    final requester = ref.watch(shellAudienceProvider) == Audience.requester;
    // The page's name in the page, and under it how the stack stands.
    // This fork: no Connections card; its Test all sits at the end of the
    // summary line.
    final heading = PageTitle.flush(
      'Settings',
      summary: requester
          ? null
          : const Row(
              children: [
                Expanded(child: _SettingsSummary()),
                TestAllConnectionsButton(),
              ],
            ),
    );
    final page = AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: GlassAppBar.inPage(
        pageTitle: 'Settings',
        leading: from == null
            ? null
            : IconButton(
                tooltip: 'Back to ${from.label}',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: goBack,
              ),
      ),
      body: SettingsMasterDetail(
        // Asked of the layout itself rather than re-derived here, so the pane
        // and the rail can never disagree about which of the two is on screen.
        child: SettingsMasterDetail.showsRail(context)
            ? SettingsSummaryPane(padding: padding, heading: heading)
            : ListView(
                padding: padding,
                children: requester
                    ? [
                        heading,
                        const DemoSettingsCard(),
                        ..._requesterIndex(context, settings),
                      ]
                    : [
                        heading,
                        const DemoSettingsCard(),
                        const SizedBox(height: AppSpacing.md),
                        ..._buildGeneralSection(context, settings),
                      ],
              ),
      ),
    );
    if (from == null) return page;
    // Android's back, which on a branch root would otherwise leave the app
    // (the shell claims it for this page). Only while this page is the one on
    // top: a pushed settings page pops first, through its own navigator, and
    // a tab tapped from here leaves the page built in its branch, where its
    // route is still its navigator's current one.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
        final shell = StatefulNavigationShell.maybeOf(context);
        if (shell != null && shell.currentIndex != NavTab.settings.index) {
          return false;
        }
        goBack();
        return true;
      },
      child: page,
    );
  }

  /// The requester's Settings (the spec of the requester, § 6.2): her
  /// account, what she sets for herself, the app, and last the one way into
  /// the operator's app. None of the operator's rows: no connections, release
  /// search, trust store, onboarding replay or reset, and no Hints, which
  /// teach the Portal her app has not.
  List<Widget> _requesterIndex(BuildContext context, SettingsModel settings) {
    return [
      const RequesterAccountCard(),
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [const SettingsHomeRow(), const SettingsNotificationsRow()],
      ),
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: settingsAboutRows(context, audience: Audience.requester),
      ),
      const SizedBox(height: AppSpacing.xl),
      const SettingsGroupCard(children: [SetUpAServiceRow()]),
      const SettingsSignature(),
    ];
  }

  List<Widget> _buildGeneralSection(
    BuildContext context,
    SettingsModel settings,
  ) {
    return [
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          // None of these carries an accent. The accent slot on a settings
          // row is the status slot; it is where the connections card puts the
          // verdict, and Region wore `AppColors.success` while Send feedback
          // wore the amber this system reserves for a fault. A preference has
          // no state to report.
          const SettingsBackgroundRow(),
          const SettingsNotificationsRow(),
          if (SettingsAnotherDeviceRow.offeredFor(settings))
            const SettingsAnotherDeviceRow(),
          const SettingsResetAppDataRow(),
        ],
      ),
    ];
  }

  // About and Danger zone build the same rows the window's summary pane does
  // (settings_app_rows.dart): they are not pages, so the rail cannot carry
  // them, and while only this index built them a wide window had no door to
  // the licence page, feedback, the donation sheet or Reset.
}

/// The line under Settings' name: how many services are set up, how many are
/// not, and where this device is, as the connections with an address away
/// say. The dot is the tone of the stack, as the Connections card paints it.
class _SettingsSummary extends ConsumerWidget {
  const _SettingsSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final readout = ref.watch(connectionsReadoutProvider);
    final where = _whereOf(ref);
    final parts = [
      '${readout.setUp} set up',
      if (readout.notSetUp.isNotEmpty) '${readout.notSetUp.length} not set up',
    ];
    final whereWords = switch (where) {
      ConnectionRoute.home => 'At home',
      ConnectionRoute.away => 'Away',
      null => null,
    };
    return Semantics(
      container: true,
      label: joinSpokenParts([...parts, ?whereWords]),
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (readout.setUp > 0)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: statusToneColor(
                  Theme.of(context).colorScheme,
                  readout.tone,
                ),
                shape: BoxShape.circle,
              ),
            ),
          Text(parts.join(dotSeparator)),
          if (whereWords != null) ...[
            Text(dotSeparator.trim()),
            Icon(
              where == ConnectionRoute.home
                  ? Icons.home_outlined
                  : Icons.public_rounded,
              size: 15,
              color: room.inkSecondary,
            ),
            Text(whereWords),
          ],
        ],
      ),
    );
  }

  /// Where this device is, as the app reckons it (`awayFromHomeProvider`):
  /// null while no connection has an address away, since without one the app
  /// cannot tell away from a server that is down.
  static ConnectionRoute? _whereOf(WidgetRef ref) {
    final anyAway = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.instances.any(
          (instance) => instance.away?.url.trim().isNotEmpty ?? false,
        ),
      ),
    );
    if (!anyAway) return null;
    return ref.watch(awayFromHomeProvider)
        ? ConnectionRoute.away
        : ConnectionRoute.home;
  }
}
