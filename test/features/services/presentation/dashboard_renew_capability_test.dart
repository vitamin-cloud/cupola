/// A decision row's Renew asks what the NPM account may change.
///
/// An expiring certificate is a decision, and its control is Renew. The
/// Certificates tab already dims its own Renew for an account that can only
/// view certificates, but the row drew the same control live for that account,
/// so the place that collects faults across services offered a write the
/// account cannot make. The row now reads the same grant. It is mounted on its
/// own: the Home leads with one line (Needs you) and no longer lists the
/// decisions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/decision_rows.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);
const _npm = 'npm';

/// One Let's Encrypt certificate ten days from lapsing, on the NPM at [_npm].
void _scriptExpiringCertificate(ProfileNetwork network) => network.on(
  _npm,
  'GET',
  '/api/nginx/certificates',
  (r) => NetworkReply.json([
    {
      'id': 7,
      'provider': 'letsencrypt',
      'nice_name': 'jellyfin.example.com',
      'domain_names': ['jellyfin.example.com'],
      'expires_on': network.now
          .add(const Duration(days: 10))
          .toUtc()
          .toIso8601String(),
    },
  ]),
);

Future<ProfileHarness> _pumpRows(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  final harness = await ProfileHarness.start(profile);
  _scriptExpiringCertificate(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const Scaffold(body: ProvidedDecisionRows()),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

Finder get _renew =>
    find.descendant(of: find.byType(DecisionRow), matching: find.text('Renew'));

/// Whether [label] sits under the gate's dim.
bool _dimmed(WidgetTester tester, Finder label) => tester
    .widgetList<Opacity>(
      find.ancestor(of: label, matching: find.byType(Opacity)),
    )
    .any((o) => o.opacity == GatedAffordance.dimmedOpacity);

void main() {

}
