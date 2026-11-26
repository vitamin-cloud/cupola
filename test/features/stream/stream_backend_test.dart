import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// The one table the Stream surfaces read a media server's providers from.
void main() {
  group('streamBackendOf', () {
    test('every media server has a backend, and no two share one', () {
      final sessions = <Object>{};
      for (final service in mediaServers) {
        final backend = streamBackendOf(service);
        expect(sessions.add(backend.sessions), isTrue, reason: service.name);
      }
    });

    test('a service that is no media server fails and names itself', () {
      for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
        expect(
          () => streamBackendOf(service),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains(service.name),
            ),
          ),
          reason: service.name,
        );
      }
    });
  });
}
