/// Every client a provider closes when its connection's settings change, and
/// what a request still sent on it fails with: never the server's failure.
///
/// Each provider below owns its client and closes it on rebuild
/// (`ref.onDispose(client.close)`), which Riverpod runs the moment the
/// connection's transport changes, before anything reads the provider again.
/// Something still holding the old client (a screen's own future, an
/// action, a second request of the same read) then sends on a closed client:
/// the Dio clients refuse it before it leaves the device, and the WebSocket
/// ones fail what was waiting. [isClosedClientFailure] has to know every one
/// of those, and nothing else.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

void main() {
  group('a provider whose read was caught by the change', () {
    test('the policy: at once, a few times, for that failure alone', () async {
      final dio = Dio()..close();
      Object? closed;
      try {
        await dio.get<dynamic>('http://nas.home.arpa:7878/api/v3/movie');
      } catch (error) {
        closed = error;
      }

      expect(noProviderRetry(0, closed!), Duration.zero);
      expect(noProviderRetry(2, closed), Duration.zero);
      expect(noProviderRetry(3, closed), isNull);
      expect(
        noProviderRetry(0, const ServiceNotConfigured(ServiceKey.radarr)),
        isNull,
      );
    });
  });
}
