/// The ranking rule, and the two things that depend on it.
///
/// Pure: the region's whole argument is an ordering and a cap, and neither needs
/// a widget to be wrong.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('rankDecisions', () {
    test('faults come before backlog, however old the backlog is', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.pendingRequest,
          'request',
          at: DateTime.utc(2020, 1, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024, 6, 1),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['stall', 'request']);
    });



    test('oldest first inside a kind', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.stalledDownload,
          'new',
          at: DateTime.utc(2024, 6),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'old',
          at: DateTime.utc(2024, 1),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'mid',
          at: DateTime.utc(2024, 3),
        ),
      ]);

      expect(ranked.map((d) => d.title), ['old', 'mid', 'new']);
    });

    test('an undated item sorts last inside its kind, never first', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.expiringCertificate, 'undated', at: null),
        _decision(
          DecisionKind.expiringCertificate,
          'dated',
          at: DateTime.utc(2024, 6),
        ),
      ]);

      // Dockge dates nothing. An item that cannot be placed honestly loses to
      // one that can: it must not inherit "just now" and outrank a real age.
      expect(ranked.map((d) => d.title), ['dated', 'undated']);
    });

    test('two undated items keep their source order', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.expiringCertificate, 'first', at: null),
        _decision(DecisionKind.expiringCertificate, 'second', at: null),
      ]);

      // `List.sort` is not stable; rows that shuffle on every rebuild read as a
      // page that cannot make up its mind.
      expect(ranked.map((d) => d.title), ['first', 'second']);
    });

    test('kinds rank worst-first, and the cap cuts from the bottom', () {
      final ranked = rankDecisions([
        _decision(
          DecisionKind.expiringCertificate,
          'cert',
          at: DateTime.utc(2024),
        ),
        _decision(
          DecisionKind.stalledDownload,
          'stall',
          at: DateTime.utc(2024),
        ),
        _decision(DecisionKind.importBlocked, 'import', at: DateTime.utc(2024)),
      ], cap: 2);

      expect(ranked.map((d) => d.title), ['stall', 'import']);
    });

    test('a cap larger than the list is not an error', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stalledDownload, 'one', at: DateTime.utc(2024)),
      ], cap: 4);

      expect(ranked, hasLength(1));
    });
  });

  // APP-04: eighteen blocked imports were eighteen rows, and the phone's three
  // slots went to the first three of them.
  group('groupDecisions', () {
    test('identical faults fold into one row that counts them', () {
      final grouped = groupDecisions([
        for (var i = 0; i < 18; i++)
          _decision(
            DecisionKind.importBlocked,
            'Episode $i',
            at: DateTime.utc(2024, 1, 18 - i),
            service: ServiceKey.sonarr,
            instanceId: 'sonarr-1',
            actionId: 7,
          ),
      ]);

      expect(grouped, hasLength(1));
      final row = grouped.single;
      expect(row.kind, DecisionKind.importBlocked);
      expect(row.count, 18);
      expect(row.title, '18 need a manual import');
      expect(row.detail, 'Sonarr\u00A0· Episode 0, Episode 1 and 16 more');
      // Ranks where its oldest member would have.
      expect(row.occurredAt, DateTime.utc(2024, 1, 1));
      // What every member agrees on travels with the group.
      expect(row.actionId, 7);
      expect(row.instanceId, 'sonarr-1');
      expect(row.route, '/stack/sonarr');
    });


    test('a lone fault stays itself', () {
      final lone = _decision(
        DecisionKind.importBlocked,
        'Dune',
        at: DateTime.utc(2024),
      );
      expect(groupDecisions([lone]).single, same(lone));
    });


    test('only a jump folds: Test and Approve act on one item', () {
      final grouped = groupDecisions([
        _decision(DecisionKind.failingIndexer, 'media', at: null),
        _decision(DecisionKind.failingIndexer, 'vpn', at: null),
        _decision(DecisionKind.pendingRequest, 'Dune', at: null),
        _decision(DecisionKind.pendingRequest, 'Alien', at: null),
      ]);

      expect(grouped.map((decision) => decision.title), [
        'media',
        'vpn',
        'Dune',
        'Alien',
      ]);
    });

    test('a value the members disagree on is dropped, never borrowed', () {
      final row = groupDecisions([
        _decision(DecisionKind.importBlocked, 'a', at: null, actionId: 1),
        _decision(DecisionKind.importBlocked, 'b', at: null, actionId: 2),
      ]).single;

      // Filing both under the first one's movie would import the second into
      // the wrong place.
      expect(row.actionId, isNull);
      expect(row.title, '2 need a manual import');
    });
  });

  group('reported problems in the pipeline', () {
    DashboardDecision problems(String instance, int count) => DashboardDecision(
      kind: DecisionKind.reportedProblems,
      id: 'seerr-issues-$instance',
      service: ServiceKey.seerr,
      title: reportedProblemsClause(count),
      detail: 'Seerr',
      occurredAt: DateTime.utc(2026, 9, 26),
      count: count,
      instanceId: instance,
      members: [
        _decision(DecisionKind.reportedProblems, 'Tears of Steel', at: null),
      ],
    );

    test('are one fault per Seerr, never folded, and keep their rows', () {
      final grouped = groupDecisions([problems('a', 3), problems('b', 1)]);

      expect(grouped, hasLength(2));
      expect(grouped.first.count, 3);
      expect(grouped.first.members, hasLength(1));
    });

    test('rank before a stuck download, as the board draws them', () {
      final ranked = rankDecisions([
        _decision(DecisionKind.stalledDownload, 'Big Buck Bunny', at: null),
        problems('a', 3),
      ]);

      expect(ranked.first.kind, DecisionKind.reportedProblems);
    });
  });

  group('decisionCapFor', () {
    test('three on the phone, four on the desktop, two at compact', () {
      expect(decisionCapFor(desktopShell: false, compact: false), 3);
      expect(decisionCapFor(desktopShell: true, compact: false), 4);
      expect(decisionCapFor(desktopShell: true, compact: true), 2);
    });
  });

  group('the vocabulary', () {
    test('only a pending request and a violation are not faults', () {
      for (final kind in DecisionKind.values) {
        expect(
          kind.isFault,
          kind != DecisionKind.pendingRequest && kind != DecisionKind.violation,
          reason: '$kind',
        );
      }
    });

    test('reported problems are reviewed, in a Seerr brought under the lens, '
        'and say how many', () {
      expect(decisionActionLabel(DecisionKind.reportedProblems), 'Review');
      expect(DecisionKind.reportedProblems.opensUnderLens, isTrue);
      expect(reportedProblemsClause(3), '3 reported problems');
      expect(reportedProblemsClause(1), '1 reported problem');
    });


    test('the stall control names the client it would open', () {
      expect(
        decisionActionLabel(
          DecisionKind.stalledDownload,
          target: ServiceKey.qbittorrent,
        ),
        'Open in qBittorrent',
      );
      // No target named: the row still offers the act rather than going blank.
      expect(
        decisionActionLabel(DecisionKind.stalledDownload),
        'Open in client',
      );
    });

    test('a blocked import names its remedy, not the client', () {
      // APP-04: filed as a stall, it said "Open in qBittorrent", the one
      // place that cannot import a file already on disk.
      expect(
        decisionActionLabel(
          DecisionKind.importBlocked,
          target: ServiceKey.sonarr,
        ),
        'Manual import',
      );
      // Readarr has no import wizard in this app; the control says where it
      // actually goes rather than promising one.
      expect(
        decisionActionLabel(
          DecisionKind.importBlocked,
          target: ServiceKey.readarr,
        ),
        'Open in Readarr',
      );
      expect(DecisionKind.importBlocked.isFault, isTrue);
    });

    test(
      'the control opens the other service, else the one that raised it',
      () {
        final ownStall = _decision(
          DecisionKind.stalledDownload,
          'a',
          at: DateTime.utc(2024),
        );
        expect(ownStall.actionTarget, ServiceKey.radarr);
        expect(
          decisionActionLabel(ownStall.kind, target: ownStall.actionTarget),
          'Open in Radarr',
        );
      },
    );

    test('an unavailable control says what it needs, and offers a way', () {
      expect(
        decisionUnavailableToast(
          DecisionKind.stalledDownload,
          ServiceKey.qbittorrent,
        ),
        'Set up qBittorrent to open this transfer.',
      );
    });
  });
}

DashboardDecision _decision(
  DecisionKind kind,
  String title, {
  required DateTime? at,
  ServiceKey service = ServiceKey.radarr,
  ServiceKey? requires,
  String instanceId = '',
  int? actionId,
  String? reason,
}) => DashboardDecision(
  kind: kind,
  id: '$kind-$title',
  service: service,
  title: title,
  detail: 'detail',
  occurredAt: at,
  requiresService: requires,
  instanceId: instanceId,
  actionId: actionId,
  reason: reason,
);
