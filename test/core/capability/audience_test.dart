import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

AudienceConnection _seerr(SeerrGrant? grant) =>
    (service: ServiceKey.seerr, seerr: grant);

/// A requester who may also see everyone's requests and choose where they go.
final _luca = _seerr(
  SeerrGrant.account(
    permissions:
        SeerrPermission.request.value |
        SeerrPermission.requestView.value |
        SeerrPermission.requestAdvanced.value,
  ),
);

void main() {
  test('a requester who can see more is still a requester', () {
    // REQUEST_VIEW and REQUEST_ADVANCED do not make a manager: approving does.
    expect(audienceOf([_luca]), Audience.requester);
    expect(
      audienceOf([
        _seerr(
          SeerrGrant.account(permissions: SeerrPermission.manageUsers.value),
        ),
      ]),
      Audience.requester,
    );
  });

  test('ADMIN on an account makes the operator', () {
    expect(
      audienceOf([
        _seerr(SeerrGrant.account(permissions: SeerrPermission.admin.value)),
      ]),
      Audience.operator,
    );
  });
}
