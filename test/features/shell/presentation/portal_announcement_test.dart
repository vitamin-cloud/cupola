import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/presentation/portal_announcement.dart';

void main() {
  group('the sentence', () {
    String say({required int services, int faults = 0, int checking = 0}) =>
        portalOpenedAnnouncement(
          PortalFloorCensus(
            services: services,
            faults: faults,
            checking: checking,
          ),
        );

    test('a clean floor says so', () {
      expect(say(services: 12), 'Portal open. 12 services, none with a fault.');
    });

    test('one fault and several read the same way', () {
      expect(
        say(services: 12, faults: 1),
        'Portal open. 12 services, 1 with a fault.',
      );
      expect(
        say(services: 12, faults: 3),
        'Portal open. 12 services, 3 with a fault.',
      );
    });

    test('one service is one service', () {
      expect(say(services: 1), 'Portal open. 1 service, none with a fault.');
    });

    test('a probe still out is said, and never counted clean', () {
      // "None with a fault" is a claim, and it cannot be made about a cell
      // that has not answered yet.
      expect(
        say(services: 12, checking: 2),
        'Portal open. 12 services, 2 checking.',
      );
      expect(
        say(services: 12, faults: 1, checking: 2),
        'Portal open. 12 services, 1 with a fault, 2 checking.',
      );
    });

    test('an empty floor says what is true', () {
      expect(say(services: 0), 'Portal open. No services are set up.');
    });
  });

  group('the census', () {});
}
