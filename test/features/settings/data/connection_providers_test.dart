import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// The pair every service client has: the lens's client and a named
/// connection's. Tested through two services built two ways (an `ApiClient`
/// service and a transport client).
void main() {
  Future<ProviderContainer> container() async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(
        configured: [ServiceKey.radarr],
      ),
    );
    addTearDown(container.dispose);
    return container;
  }



}
