import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/fixtures.dart';

int _bits(List<SeerrPermission> permissions) =>
    permissions.fold(0, (mask, permission) => mask | permission.value);

/// Seerr 3.5.0 as it ships in the fixture: a default 4K Radarr, no 4K
/// Sonarr.
final _server = SeerrServerFacts.fromPublicSettings(
  jsonFixtureMap('seerr/public_settings_seerr_3.5.0.json'),
  version: '3.5.0',
);

const _key = SeerrGrant.apiKey();

/// The household default.
final _anna = SeerrGrant.account(permissions: SeerrPermission.request.value);

/// A requester who may see everyone's requests and pick their destination.
final _luca = SeerrGrant.account(
  permissions: _bits([
    SeerrPermission.request,
    SeerrPermission.requestView,
    SeerrPermission.requestAdvanced,
  ]),
);

final _manager = SeerrGrant.account(
  permissions: _bits([SeerrPermission.request, SeerrPermission.manageRequests]),
);

final _moviesOnly = SeerrGrant.account(
  permissions: SeerrPermission.requestMovie.value,
);

final _with4k = SeerrGrant.account(
  permissions: _bits([SeerrPermission.request, SeerrPermission.request4k]),
);

RoleGate _operator(SeerrGrant? grant) =>
    RoleGate(audience: Audience.operator, grant: grant, server: _server);

RoleGate _requester(SeerrGrant? grant) =>
    RoleGate(audience: Audience.requester, grant: grant, server: _server);

/// `L` live, `D` dimmed, `A` absent; one column per [SeerrAbility], in its
/// order:
///
///     request  request4k  autoApproved  autoApproved4k  chooseDestination
///     bypassQuota  approve  manageMedia  seeEveryonesRequests
///     cancelOwnPending  viewIssues  manageIssues  manageUsers  readSettings
///     reportIssue
final _operatorActions = <String, (RoleGate, String)>{
  // The key answers as the app does today: everything live.
  'operator, the key': (_operator(_key), 'L L L L L L L L L L L L L L L'),
  // A friend's Seerr account beside the operator's own: dimmed, never hidden.
  'operator, a requester account': (
    _operator(_anna),
    'L D D D D D D D D L D D D D D',
  ),
  'operator, a manager account': (
    _operator(_manager),
    'L D L L L L L L L L D D D D D',
  ),
  'operator, no Seerr on the surface': (
    const RoleGate.operator(),
    'L L L L L L L L L L L L L L L',
  ),
  // The requester's own: live or dimmed. The operator's: never drawn.
  'requester, the household default': (
    _requester(_anna),
    'L D D D A A A A A L A A A A D',
  ),
  // REQUEST_ADVANCED and REQUEST_VIEW change nothing for the requester: the
  // pickers would read "Radarr 4K", and other people's names stay theirs.
  'requester, who may see and pick more': (
    _requester(_luca),
    'L D D D A A A A A L A A A A D',
  ),
  'requester, no Seerr on the surface': (
    _requester(null),
    'A A A A A A A A A A A A A A A',
  ),
};

GateVerdict? _parse(String cell) => switch (cell) {
  'L' => const Live(),
  'A' => const Absent(),
  _ => null,
};

void main() {
  group('operatorAction', () {
    for (final MapEntry(key: name, value: (gate, row))
        in _operatorActions.entries) {
      test(name, () {
        final cells = row.split(' ');
        expect(cells, hasLength(SeerrAbility.values.length));
        for (final (index, ability) in SeerrAbility.values.indexed) {
          final verdict = gate.operatorAction(ability);
          final expected = _parse(cells[index]);
          if (expected == null) {
            expect(verdict, isA<Dimmed>(), reason: ability.name);
          } else {
            expect(verdict, expected, reason: ability.name);
          }
        }
      });
    }

    test('an operator reads which account cannot, by its server name', () {
      final gate = RoleGate(
        audience: Audience.operator,
        grant: _anna,
        server: SeerrServerFacts.fromPublicSettings({
          ...jsonFixtureMap('seerr/public_settings_seerr_3.5.0.json'),
          'applicationTitle': 'Casa Requests',
        }),
      );
      expect(
        gate.operatorAction(SeerrAbility.approve),
        const Dimmed("Your account on Casa Requests can't approve requests."),
      );
      expect(
        gate.operatorAction(SeerrAbility.manageMedia).reason,
        "Your account on Casa Requests can't manage media.",
      );
      // Without the server's facts it is still named, by the service.
      expect(
        RoleGate(
          audience: Audience.operator,
          grant: _anna,
        ).operatorAction(SeerrAbility.chooseDestination).reason,
        "Your account on Seerr can't choose where requests go.",
      );
    });

    test('the requester is told about themselves, never a service', () {
      expect(
        _requester(_anna).operatorAction(SeerrAbility.autoApproved).reason,
        "You can't skip approval on this server.",
      );
    });
  });

  group('requestAction', () {
    final restricted = SeerrQuota(
      movie: const SeerrQuotaStatus(
        days: 7,
        limit: 10,
        used: 10,
        remaining: 0,
        restricted: true,
      ),
    );
    final rows = <(String, GateVerdict Function(), GateVerdict)>[
      (
        'the key asks for a movie',
        () => _operator(_key).requestAction(SeerrMediaKind.movie),
        const Live(),
      ),
      (
        'the key asks for a 4K movie: the server has a 4K Radarr',
        () => _operator(_key).requestAction(SeerrMediaKind.movie, is4k: true),
        const Live(),
      ),
      (
        'the key asks for a 4K series: the server has no 4K Sonarr',
        () => _operator(_key).requestAction(SeerrMediaKind.tv, is4k: true),
        const Absent(),
      ),
      (
        'a requester asks for a series',
        () => _requester(_anna).requestAction(SeerrMediaKind.tv),
        const Live(),
      ),
      (
        'a requester without 4K is not offered it',
        () => _requester(_anna).requestAction(SeerrMediaKind.movie, is4k: true),
        const Absent(),
      ),
      (
        'nor is an operator holding that account',
        () => _operator(_anna).requestAction(SeerrMediaKind.movie, is4k: true),
        const Absent(),
      ),
      (
        'a requester with 4K, on a server with a 4K Radarr',
        () =>
            _requester(_with4k).requestAction(SeerrMediaKind.movie, is4k: true),
        const Live(),
      ),
      (
        'a requester with 4K, on a server without a 4K Sonarr',
        () => _requester(_with4k).requestAction(SeerrMediaKind.tv, is4k: true),
        const Absent(),
      ),
      (
        'a requester who may ask only for movies asks for a series',
        () => _requester(_moviesOnly).requestAction(SeerrMediaKind.tv),
        const Dimmed("You can't ask for series on this server."),
      ),
      (
        'the operator holding that account',
        () => _operator(_moviesOnly).requestAction(SeerrMediaKind.tv),
        const Dimmed("Your account on Seerr can't ask for series."),
      ),
      (
        'a requester at the movie limit',
        () => _requester(
          _anna,
        ).requestAction(SeerrMediaKind.movie, quota: restricted),
        const Dimmed(
          "You've asked for 10 movies in the last 7 days, the most this "
          'server allows.',
        ),
      ),
      (
        'the same requester asks for a series',
        () => _requester(
          _anna,
        ).requestAction(SeerrMediaKind.tv, quota: restricted),
        const Live(),
      ),
      (
        'an operator holding an account at its limit',
        () => _operator(
          _anna,
        ).requestAction(SeerrMediaKind.movie, quota: restricted),
        const Dimmed(
          'Your account on Seerr has asked for 10 movies in the last 7 days, '
          'the most the server allows.',
        ),
      ),
      (
        'no Seerr on the surface: the operator as today',
        () => const RoleGate.operator().requestAction(SeerrMediaKind.movie),
        const Live(),
      ),
      (
        'no Seerr on the surface: nothing for the requester to ask',
        () => _requester(null).requestAction(SeerrMediaKind.movie),
        const Absent(),
      ),
    ];
    for (final (name, verdict, expected) in rows) {
      test(name, () => expect(verdict(), expected));
    }

    test('a manager at the limit is dimmed too', () {
      // Going past the limit is an option the request sheet sends
      // (`ignoreQuota`), not this verdict: without it the server refuses.
      expect(
        _operator(
          _manager,
        ).requestAction(SeerrMediaKind.movie, quota: restricted),
        isA<Dimmed>(),
      );
    });

    test('the limit, said for every shape of quota', () {
      String? reason(SeerrMediaKind kind, SeerrQuotaStatus status) =>
          _requester(_anna)
              .requestAction(
                kind,
                quota: kind == SeerrMediaKind.movie
                    ? SeerrQuota(movie: status)
                    : SeerrQuota(tv: status),
              )
              .reason;

      // A series quota counts seasons (`User.ts` `getQuota`).
      expect(
        reason(
          SeerrMediaKind.tv,
          const SeerrQuotaStatus(days: 1, limit: 1, used: 1, restricted: true),
        ),
        "You've asked for 1 season in the last day, the most this server "
        'allows.',
      );
      expect(
        reason(
          SeerrMediaKind.tv,
          const SeerrQuotaStatus(limit: 5, used: 5, restricted: true),
        ),
        "You've asked for 5 seasons, the most this server allows.",
      );
      expect(
        reason(
          SeerrMediaKind.movie,
          const SeerrQuotaStatus(limit: 1, used: 1, days: 30, restricted: true),
        ),
        "You've asked for 1 movie in the last 30 days, the most this server "
        'allows.',
      );
      // Restricted without a limit to name: said without a number.
      expect(
        reason(SeerrMediaKind.movie, const SeerrQuotaStatus(restricted: true)),
        "You've asked for as many movies as this server allows.",
      );
      // A limit not yet reached dims nothing.
      expect(
        reason(
          SeerrMediaKind.movie,
          const SeerrQuotaStatus(limit: 10, used: 9, remaining: 1),
        ),
        isNull,
      );
    });
  });

  group('cancelAction', () {
    final rows = <(String, RoleGate, bool own, bool waiting, GateVerdict)>[
      ('the key, anybody\'s', _operator(_key), false, false, const Live()),
      (
        'a manager, anybody\'s',
        _operator(_manager),
        false,
        false,
        const Live(),
      ),
      (
        'a requester, own and waiting',
        _requester(_anna),
        true,
        true,
        const Live(),
      ),
      (
        'a requester, own and approved',
        _requester(_anna),
        true,
        false,
        const Absent(),
      ),
      (
        'a requester, somebody else\'s',
        _requester(_anna),
        false,
        true,
        const Absent(),
      ),
      (
        'an operator holding a requester account, own and approved',
        _operator(_anna),
        true,
        false,
        const Dimmed(
          'Only a request still waiting for approval can be canceled.',
        ),
      ),
      (
        'an operator holding a requester account, somebody else\'s',
        _operator(_anna),
        false,
        true,
        const Dimmed(
          "Your account on Seerr can't cancel other people's requests.",
        ),
      ),
      (
        'no Seerr, the operator',
        const RoleGate.operator(),
        false,
        false,
        const Live(),
      ),
      ('no Seerr, the requester', _requester(null), true, true, const Absent()),
    ];
    for (final (name, gate, own, waiting, expected) in rows) {
      test(name, () {
        expect(
          gate.cancelAction(own: own, waitingForApproval: waiting),
          expected,
        );
      });
    }
  });

  group('what a surface shows', () {
    test('names of other requesters', () {
      expect(_operator(_key).showsRequesterNames, isTrue);
      expect(const RoleGate.operator().showsRequesterNames, isTrue);
      expect(_operator(_luca).showsRequesterNames, isTrue);
      // The server filters the list down to the account's own anyway.
      expect(_operator(_anna).showsRequesterNames, isFalse);
      // Never for the requester, REQUEST_VIEW or not.
      expect(_requester(_luca).showsRequesterNames, isFalse);
      expect(_requester(_anna).showsRequesterNames, isFalse);
    });

    test('the control room', () {
      expect(_operator(_anna).showsControlRoom, isTrue);
      expect(_requester(_anna).showsControlRoom, isFalse);
    });

    test('the voice of a failure', () {
      expect(_operator(_key).faultVoice, FaultVoice.full);
      expect(_operator(_anna).faultVoice, FaultVoice.full);
      expect(_requester(_anna).faultVoice, FaultVoice.brief);
    });

    test('4K is offered where the account and the server both can', () {
      expect(_operator(_key).offers4k(SeerrMediaKind.movie), isTrue);
      expect(_operator(_key).offers4k(SeerrMediaKind.tv), isFalse);
      expect(_requester(_with4k).offers4k(SeerrMediaKind.movie), isTrue);
      expect(_requester(_anna).offers4k(SeerrMediaKind.movie), isFalse);
      // Without the server's facts nobody knows there is a 4K server.
      expect(
        const RoleGate(
          audience: Audience.operator,
          grant: _key,
        ).offers4k(SeerrMediaKind.movie),
        isFalse,
      );
    });
  });

  group('resolveIssueAction', () {
    final viewer = SeerrGrant.account(
      permissions:
          SeerrPermission.request.value | SeerrPermission.viewIssues.value,
    );
    final reporter = SeerrGrant.account(
      permissions:
          SeerrPermission.request.value | SeerrPermission.createIssues.value,
    );
    final rows = <(String, RoleGate, bool own, GateVerdict)>[
      ('the key, anybody\'s', _operator(_key), false, const Live()),
      ('a reporter, own', _operator(reporter), true, const Live()),
      (
        'a reporter, somebody else\'s',
        _operator(reporter),
        false,
        const Dimmed("Your account on Seerr can't manage issues."),
      ),
      (
        'a viewer, own',
        _operator(viewer),
        true,
        const Dimmed("Your account on Seerr can't manage issues."),
      ),
      ('a requester, own', _requester(reporter), true, const Live()),
      (
        'a requester, somebody else\'s',
        _requester(reporter),
        false,
        const Absent(),
      ),
      (
        'a requester without CREATE, own',
        _requester(_anna),
        true,
        const Dimmed("You can't report problems on this server."),
      ),
      (
        'no Seerr, the operator',
        const RoleGate.operator(),
        false,
        const Live(),
      ),
    ];
    for (final (name, gate, own, expected) in rows) {
      test(name, () => expect(gate.resolveIssueAction(own: own), expected));
    }
  });

  group('reportIssueAction', () {
    final reporter = SeerrGrant.account(
      permissions: SeerrPermission.createIssues.value,
    );
    final keeper = SeerrGrant.account(
      permissions: SeerrPermission.manageIssues.value,
    );
    final rows = <(String, RoleGate, GateVerdict)>[
      ('the key', _operator(_key), const Live()),
      ('no Seerr, the operator', const RoleGate.operator(), const Live()),
      (
        'no Seerr, the requester: no row at all',
        _requester(null),
        const Absent(),
      ),
      ('a requester with CREATE', _requester(reporter), const Live()),
      ('a requester with MANAGE', _requester(keeper), const Live()),
      (
        'a requester without it: dimmed, the reason on tap',
        _requester(_anna),
        const Dimmed("You can't report problems on this server."),
      ),
      ('an operator account with CREATE', _operator(reporter), const Live()),
      (
        'an operator account without it',
        _operator(_anna),
        const Dimmed("Your account on Seerr can't report problems."),
      ),
    ];
    for (final (name, gate, expected) in rows) {
      test(name, () => expect(gate.reportIssueAction(), expected));
    }

    test('an operator reads which server, by its name', () {
      final gate = RoleGate(
        audience: Audience.operator,
        grant: _anna,
        server: SeerrServerFacts.fromPublicSettings({
          ...jsonFixtureMap('seerr/public_settings_seerr_3.5.0.json'),
          'applicationTitle': 'Casa Requests',
        }),
      );
      expect(
        gate.reportIssueAction().reason,
        "Your account on Casa Requests can't report problems.",
      );
    });
  });

  group('the conversation of an issue', () {
    final viewer = SeerrGrant.account(
      permissions: SeerrPermission.viewIssues.value,
    );
    final reporter = SeerrGrant.account(
      permissions: SeerrPermission.createIssues.value,
    );
    final keeper = SeerrGrant.account(
      permissions: SeerrPermission.manageIssues.value,
    );
    const noManage = Dimmed("Your account on Seerr can't manage issues.");
    const noReport = Dimmed("You can't report problems on this server.");

    group('comment, resolve and reopen', () {
      final rows = <(String, RoleGate, bool own, GateVerdict)>[
        ('the key, anybody\'s', _operator(_key), false, const Live()),
        (
          'an operator manager, anybody\'s',
          _operator(keeper),
          false,
          const Live(),
        ),
        ('an operator reporter, own', _operator(reporter), true, const Live()),
        (
          'an operator reporter, anybody\'s',
          _operator(reporter),
          false,
          noManage,
        ),
        ('an operator viewer, own', _operator(viewer), true, noManage),
        ('a requester reporter, own', _requester(reporter), true, const Live()),
        (
          'a requester reporter, anybody\'s',
          _requester(reporter),
          false,
          const Absent(),
        ),
        ('a requester without CREATE, own', _requester(_anna), true, noReport),
        (
          'a requester without CREATE, anybody\'s',
          _requester(_anna),
          false,
          const Absent(),
        ),
        (
          'a requester manager account, anybody\'s',
          _requester(keeper),
          false,
          const Absent(),
        ),
        (
          'no Seerr, the operator',
          const RoleGate.operator(),
          false,
          const Live(),
        ),
        ('no Seerr, the requester', _requester(null), true, const Absent()),
      ];
      for (final (name, gate, own, expected) in rows) {
        test('comment: $name', () {
          expect(gate.commentOnIssueAction(own: own), expected);
        });
        test('resolve: $name', () {
          expect(gate.resolveIssueAction(own: own), expected);
        });
      }
    });

    group('edit a reply: only its author', () {
      final rows = <(String, RoleGate, bool own, GateVerdict)>[
        ('the key', _operator(_key), true, const Live()),
        (
          'an operator manager, own reply',
          _operator(keeper),
          true,
          const Live(),
        ),
        (
          'an operator manager, another\'s reply',
          _operator(keeper),
          false,
          noManage,
        ),
        (
          'an operator reporter, own reply',
          _operator(reporter),
          true,
          const Live(),
        ),
        (
          'an operator reporter, another\'s',
          _operator(reporter),
          false,
          noManage,
        ),
        (
          'an operator without CREATE, own reply',
          _operator(_anna),
          true,
          noManage,
        ),
        (
          'a requester reporter, own reply',
          _requester(reporter),
          true,
          const Live(),
        ),
        (
          'a requester reporter, another\'s',
          _requester(reporter),
          false,
          const Absent(),
        ),
        (
          'a requester manager account, another\'s',
          _requester(keeper),
          false,
          const Absent(),
        ),
        (
          'a requester without CREATE, own reply',
          _requester(_anna),
          true,
          noReport,
        ),
        ('no Seerr, the requester', _requester(null), true, const Absent()),
      ];
      for (final (name, gate, own, expected) in rows) {
        test(name, () => expect(gate.editReplyAction(own: own), expected));
      }
    });

    group('delete a reply: own with CREATE, anybody\'s with MANAGE', () {
      final rows = <(String, RoleGate, bool own, GateVerdict)>[
        ('the key', _operator(_key), false, const Live()),
        (
          'an operator manager, another\'s reply',
          _operator(keeper),
          false,
          const Live(),
        ),
        (
          'an operator reporter, own reply',
          _operator(reporter),
          true,
          const Live(),
        ),
        (
          'an operator reporter, another\'s',
          _operator(reporter),
          false,
          noManage,
        ),
        (
          'a requester reporter, own reply',
          _requester(reporter),
          true,
          const Live(),
        ),
        (
          'a requester reporter, another\'s',
          _requester(reporter),
          false,
          const Absent(),
        ),
        (
          'a requester without CREATE, own reply',
          _requester(_anna),
          true,
          noReport,
        ),
        ('no Seerr, the requester', _requester(null), true, const Absent()),
      ];
      for (final (name, gate, own, expected) in rows) {
        test(name, () => expect(gate.deleteReplyAction(own: own), expected));
      }
    });

    group('delete the issue', () {
      final rows = <(String, RoleGate, bool own, int comments, GateVerdict)>[
        ('the key, answered', _operator(_key), false, 4, const Live()),
        (
          'an operator manager, answered',
          _operator(keeper),
          false,
          4,
          const Live(),
        ),
        (
          'an operator reporter, own, one comment',
          _operator(reporter),
          true,
          1,
          const Live(),
        ),
        (
          'an operator reporter, own, two comments',
          _operator(reporter),
          true,
          2,
          noManage,
        ),
        (
          'an operator reporter, anybody\'s',
          _operator(reporter),
          false,
          1,
          noManage,
        ),
        (
          'a requester reporter, own, one comment',
          _requester(reporter),
          true,
          1,
          const Live(),
        ),
        (
          'a requester reporter, own, two comments',
          _requester(reporter),
          true,
          2,
          noReport,
        ),
        (
          'a requester reporter, anybody\'s',
          _requester(reporter),
          false,
          1,
          const Absent(),
        ),
        (
          'no Seerr, the operator',
          const RoleGate.operator(),
          false,
          3,
          const Live(),
        ),
        ('no Seerr, the requester', _requester(null), true, 1, const Absent()),
      ];
      for (final (name, gate, own, comments, expected) in rows) {
        test(name, () {
          expect(
            gate.deleteIssueAction(own: own, commentCount: comments),
            expected,
          );
        });
      }
    });

    test('an operator reads which server, by its name', () {
      final gate = RoleGate(
        audience: Audience.operator,
        grant: reporter,
        server: SeerrServerFacts.fromPublicSettings({
          ...jsonFixtureMap('seerr/public_settings_seerr_3.5.0.json'),
          'applicationTitle': 'Casa Requests',
        }),
      );
      expect(
        gate.resolveIssueAction(own: false).reason,
        "Your account on Casa Requests can't manage issues.",
      );
    });
  });

  group('every reason the gate gives', () {
    final gates = [
      for (final grant in [_anna, _moviesOnly, _manager, _luca]) ...[
        _operator(grant),
        _requester(grant),
      ],
    ];
    final quota = SeerrQuota(
      movie: const SeerrQuotaStatus(limit: 3, days: 7, restricted: true),
      tv: const SeerrQuotaStatus(restricted: true),
    );
    final reasons = {
      for (final gate in gates) ...[
        for (final ability in SeerrAbility.values)
          for (final kind in [...SeerrMediaKind.values, null])
            gate.operatorAction(ability, kind: kind).reason,
        for (final kind in SeerrMediaKind.values) ...[
          gate.requestAction(kind).reason,
          gate.requestAction(kind, quota: quota).reason,
        ],
        for (final own in [true, false])
          for (final waiting in [true, false])
            gate.cancelAction(own: own, waitingForApproval: waiting).reason,
        gate.reportIssueAction().reason,
        for (final own in [true, false]) ...[
          gate.resolveIssueAction(own: own).reason,
          gate.commentOnIssueAction(own: own).reason,
          gate.editReplyAction(own: own).reason,
          gate.deleteReplyAction(own: own).reason,
          for (final count in [1, 2])
            gate.deleteIssueAction(own: own, commentCount: count).reason,
        ],
      ],
    }.whereType<String>().toSet();

    test('there are some', () => expect(reasons.length, greaterThan(20)));

    test('is a sentence: a capital, a full stop, no em dash', () {
      for (final reason in reasons) {
        expect(reason, isNot(contains('\u2014')), reason: reason);
        expect(reason, endsWith('.'), reason: reason);
        expect(reason[0], reason[0].toUpperCase(), reason: reason);
        expect(reason, isNot(contains('  ')), reason: reason);
      }
    });

    test('names no service but Seerr, and the requester none at all', () {
      final names = [for (final service in ServiceKey.values) service.title];
      for (final gate in gates) {
        for (final ability in SeerrAbility.values) {
          final reason = gate.operatorAction(ability).reason;
          if (reason == null) continue;
          for (final name in names) {
            if (name == 'Seerr' && gate.audience == Audience.operator) continue;
            expect(reason, isNot(contains(name)), reason: reason);
          }
        }
      }
    });
  });

  test('printing a gate prints no account data', () {
    final grant = SeerrGrant.fromWhoAmI({
      'id': 7,
      'email': 'sentinel@example.com',
      'displayName': 'Sentinel',
      'permissions': 32,
    });
    final gate = RoleGate(
      audience: Audience.requester,
      grant: grant,
      server: _server,
    );
    expect(gate.toString(), isNot(contains('entinel')));
    expect(gate.toString(), isNot(contains('@')));
    expect(gate.toString(), contains('requester'));
  });

  group('a verdict', () {
    test('says whether it acts, whether it is drawn, and why not', () {
      expect(const Live().acts, isTrue);
      expect(const Live().isDrawn, isTrue);
      expect(const Live().reason, isNull);
      expect(const Dimmed('Why.').acts, isFalse);
      expect(const Dimmed('Why.').isDrawn, isTrue);
      expect(const Dimmed('Why.').reason, 'Why.');
      expect(const Absent().acts, isFalse);
      expect(const Absent().isDrawn, isFalse);
      expect(const Absent().reason, isNull);
    });

    test('is a value', () {
      expect(const Dimmed('a'), const Dimmed('a'));
      expect(const Dimmed('a'), isNot(const Dimmed('b')));
      expect(const Live(), isNot(const Absent()));
    });
  });
}
