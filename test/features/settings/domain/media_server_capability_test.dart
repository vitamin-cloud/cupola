import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// What a service is, asked as a capability: the sites that used to name
/// Jellyfin and Plex read these, and the lists below are what they walk.
void main() {
  group('the media server capabilities', () {
    test('the media servers are the services that answer isMediaServer', () {
      expect(mediaServers, ServiceKey.values.where((s) => s.isMediaServer));
      expect(mediaServers, isNotEmpty);
    });

    test('a media server says who is playing', () {
      for (final service in mediaServers) {
        expect(service.givesSessions, isTrue, reason: service.name);
      }
    });

    test('the playing services are in registry order and hold every '
        'media server, and only Tracearr beside them', () {
      expect(sessionServices, ServiceKey.values.where((s) => s.givesSessions));
      expect(sessionServices, containsAll(mediaServers));
      expect(sessionServices.where((s) => !s.isMediaServer), []);
    });

    test('what speaks the MediaBrowser API is a media server that picks a '
        'viewer', () {
      for (final service in ServiceKey.values.where(
        (s) => s.speaksMediaBrowser,
      )) {
        expect(service.isMediaServer, isTrue, reason: service.name);
        expect(service.needsViewerSelection, isTrue, reason: service.name);
      }
    });

    test('only Jellyfin hides its library list from a household member', () {
      // Measured on Emby 4.10.2: `/Library/VirtualFolders/Query` answers a
      // member's token, while Users, Devices and Tasks are refused.
      expect(ServiceKey.values.where((s) => s.librariesNeedAdministrator), [
        ServiceKey.jellyfin,
      ]);
    });

    test('a service that is no media server is handed none of their lists', () {
      for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
        expect(mediaServers, isNot(contains(service)), reason: service.name);
        expect(service.speaksMediaBrowser, isFalse, reason: service.name);
      }
    });

    test('the Stream band mounts the visit\'s connection', () {
      for (final service in ServiceDomain.stream.services) {
        expect(service.mountsConnectionInView, isTrue, reason: service.name);
      }
      for (final service in ServiceKey.values.where(
        (s) => s.domain != ServiceDomain.stream,
      )) {
        expect(service.mountsConnectionInView, isFalse, reason: service.name);
      }
    });

    test('every media server sits in the Stream band', () {
      // The band groups what is for watching; a media server out of it would
      // have no room in the stack for its libraries and sessions.
      for (final service in mediaServers) {
        expect(service.domain, ServiceDomain.stream, reason: service.name);
      }
    });
  });
}
