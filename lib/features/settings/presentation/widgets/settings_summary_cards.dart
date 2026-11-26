import 'package:flutter/material.dart';
import 'package:cupola/features/home/presentation/widgets/settings_home_row.dart';
import 'package:cupola/features/outside/presentation/settings_notifications_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/connections_readout.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/requester_settings_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_app_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/test_all_connections_button.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/demo/presentation/demo_settings_card.dart';

/// The six cards of the settings summary, and the rule all six obey: **print
/// only what is wrong.**
///
/// A settings index that lists every preference at its current value is an
/// inventory, and nobody audits an inventory. Each card here leads with one
/// readout and then says nothing at all unless something about that area is
/// actually worth acting on: a service that is not answering, a pinned
/// certificate no service reaches any more, a notification permission the OS is
/// refusing, a setting that does not do what its name suggests. A quiet card is
/// the useful answer, not a missing one.
///
/// Every state word comes from `describeConnection` and every colour from
/// `statusToneColor`, for the reason the vocabulary exists: the summary, the
/// connections list and the connection form must not describe one failure three
/// different ways.
///
/// **After the six, three cards that are doors rather than readouts:**
/// Onboarding, About and Danger zone. Those rows are not pages, so the rail
/// cannot carry them, and while only the phone index built them a window this
/// wide had no way to the licence page, the feedback address, the donation
/// sheet, the onboarding replay or Reset. They are the phone's own rows
/// (`settings_app_rows.dart`) under the phone's own labels, in the phone's
/// order; Reset keeps its confirmation.
class SettingsSummaryPane extends ConsumerWidget {
  const SettingsSummaryPane({super.key, required this.padding, this.heading});

  final EdgeInsetsGeometry padding;

  /// The page's name over the cards (`PageTitle`), or null.
  final Widget? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The requester's pane holds what her phone's index holds (the spec of
    // the requester, § 6.2), in the pane's grammar.
    if (ref.watch(shellAudienceProvider) == Audience.requester) {
      return ListView(
        padding: padding,
        children: [
          ?heading,
          const DemoSettingsCard(),
          const RequesterAccountCard(),
          const SizedBox(height: AppSpacing.xl),
          const _SummaryCard(
            label: 'General',
            children: [SettingsHomeRow(), SettingsNotificationsRow()],
          ),
          const SizedBox(height: AppSpacing.xl),
          _SummaryCard(
            label: 'About',
            children: settingsAboutRows(context, audience: Audience.requester),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SettingsGroupCard(children: [SetUpAServiceRow()]),
        ],
      );
    }
    final offersCode = SettingsAnotherDeviceRow.offeredFor(
      ref.watch(currentSettingsProvider),
    );
    return ListView(
      padding: padding,
      children: [
        ?heading,
        const DemoSettingsCard(),
        const ConnectionsSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        // The same rows as the phone's General section.
        _SummaryCard(
          label: 'General',
          children: [
            const SettingsBackgroundRow(),
            const SettingsNotificationsRow(),
            const SettingsRevisitOnboardingRow(),
            if (offersCode) const SettingsAnotherDeviceRow(),
            const SettingsResetAppDataRow(),
          ],
        ),
      ],
    );
  }
}

/// The stack's connections as one readout: every service set up, how it
/// answered, and the ones not set up. The Connections card leads with it and
/// the Settings page's line under its name says it again in short.
final connectionsReadoutProvider = Provider.autoDispose<ConnectionsReadout>((
  ref,
) {
  final settings = ref.watch(currentSettingsProvider);
  final states = <ServiceKey, ConnectionPresentation>{};
  final notSetUp = <ServiceKey>[];
  // Counted by the Stack's rule (`foldedServiceHealthProvider`): a service
  // that answered with a refusal or a fault answered. Its fault is still
  // named in its group.
  var answered = 0;
  for (final service in ServiceKey.values) {
    if (!settings.hasServiceConnection(service)) {
      notSetUp.add(service);
      continue;
    }
    final async = ref.watch(serviceDiagnosisProvider(service));
    final diagnosis = async.isLoading ? null : async.asData?.value;
    final reason = diagnosis?.reason;
    if (diagnosis?.status == ServiceConnectionStatus.connected ||
        (reason != null &&
            !failureDidNotAnswer(reason) &&
            reason != ServiceFailureReason.sessionEnded)) {
      answered++;
    }
    states[service] = describeConnection(
      service,
      // Loading is a state of its own in the vocabulary, and a provider that
      // threw says exactly what a failed probe says: we could not confirm it.
      status: async.isLoading
          ? ServiceConnectionStatus.checking
          : (async.asData?.value.status ??
                ServiceConnectionStatus.disconnected),
      reason: async.asData?.value.reason,
      gateway: async.asData?.value.gateway,
    );
  }
  return ConnectionsReadout.from(
    states: states,
    notSetUp: notSetUp,
    answeringServices: answered,
  );
});

/// The connections card: the count, then only the connections that are wrong.
///
/// Shared by the summary pane and the phone index rather than drawn twice:
/// the phone's header card and the window's first card are the same statement
/// about the same stack, and two implementations of it would be two chances to
/// count "set up" differently.
class ConnectionsSummaryCard extends ConsumerWidget {
  const ConnectionsSummaryCard({super.key});

  /// The most not-yet-configured services to name before the count carries it
  /// alone. On a fresh install every service is unset, and nineteen names is
  /// not a to-do list, it is wallpaper.
  static const int _maxNamedUnset = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final readout = ref.watch(connectionsReadoutProvider);
    final notSetUp = readout.notSetUp;

    return _SummaryCard(
      label: 'Connections',
      action: const TestAllConnectionsButton(),
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.hub_rounded),
          title: readout.summary,
          accentColor: statusToneColor(colorScheme, readout.tone),
          semanticLabel: readout.summary,
          semanticHint: 'opens the connections list',
          onTap: () => context.push('/settings/connections'),
        ),
        for (final group in readout.faults)
          _GroupRow(group: group, onTap: () => _openGroup(context, group)),
        if (notSetUp.isNotEmpty && notSetUp.length <= _maxNamedUnset)
          _GroupRow(
            group: ConnectionGroup(
              // Through the vocabulary rather than around it: "Not set up" is
              // what `describeConnection` calls a service with no address, and
              // this card must not coin a second phrase for it.
              presentation: describeConnection(
                notSetUp.first,
                status: ServiceConnectionStatus.notConfigured,
              ),
              services: notSetUp,
            ),
            onTap: () => context.push('/settings/connections'),
          ),
      ],
    );
  }

  /// One failing service opens its own form; several open the list, because
  /// there is no one form that would answer for all of them.
  void _openGroup(BuildContext context, ConnectionGroup group) {
    if (group.services.length == 1) {
      context.push('/settings/service/${group.services.single.routeParam}');
      return;
    }
    context.push('/settings/connections');
  }
}

/// One row for one connection state: the services in it, and the vocabulary's
/// word for what they are doing.
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onTap});

  final ConnectionGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The card is an elevated container, so the tone has to be walked against
    // *that* surface rather than the page behind it.
    final tone = statusToneColor(
      colorScheme,
      group.presentation.tone,
      surface: colorScheme.surfaceContainer,
    );

    return SettingsCard.grouped(
      leading: Icon(group.presentation.icon),
      title: group.names,
      subtitle: group.presentation.label,
      subtitleColor: tone,
      accentColor: tone,
      semanticLabel: '${group.names}, ${group.presentation.label}',
      semanticHint: group.services.length == 1
          ? 'opens the ${group.services.single.title} connection settings'
          : 'opens the connections list',
      onTap: onTap,
    );
  }
}

/// A card: its eyebrow, an optional command of its own, and its rows.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.children,
    this.action,
  });

  final String label;
  final List<Widget> children;

  /// A command that belongs to this card rather than to the pane it opens:
  /// "Test all" is the only one so far. The door is the first row; this is not
  /// a second door.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same eyebrow every settings group on the phone index wears, so a
        // card that has a command does not also grow a different kind of
        // heading. The label excludes its own subtree from semantics and the
        // action is its sibling, so the button keeps a focus stop of its own.
        Row(
          children: [
            Expanded(child: SettingsSectionLabel(label)),
            ?action,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(children: children),
      ],
    );
  }
}
