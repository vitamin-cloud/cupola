import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Object? _fixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync());

const _page = '<!DOCTYPE html><html><body>Welcome to nginx!</body></html>';

/// What each service's own probe answers, from the fixtures where there is
/// one and from the shape its client parses where there is not.
final Map<ServiceKey, Object?> _genuine = {
  ServiceKey.radarr: {'appName': 'Radarr', 'version': '5.26.2.10099'},
  ServiceKey.sonarr: {'appName': 'Sonarr', 'version': '4.0.15.2941'},
  ServiceKey.seerr: {'version': '2.7.3', 'commitTag': 'v2.7.3'},
  ServiceKey.jellyfin: _fixture('jellyfin/system_info_public.json'),
  ServiceKey.qbittorrent: 'v5.1.2',
  ServiceKey.truenas: {'version': 'TrueNAS-SCALE-25.04.2'},
  ServiceKey.dockge: '1.5.0',
};

void main() {
  group('identifyProbeAnswer', () {
    test('every service recognises its own answer', () {
      expect(_genuine.keys, containsAll(ServiceKey.values));
      for (final service in ServiceKey.values) {
        expect(
          identifyProbeAnswer(service, _genuine[service]),
          ProbeIdentity.matches,
          reason: service.title,
        );
      }
    });

    test('a web page is not the service, for every service that reads one', () {
      for (final service in ServiceKey.values) {
        if (service == ServiceKey.truenas || service == ServiceKey.dockge) {
          continue;
        }
        expect(
          identifyProbeAnswer(service, _page),
          ProbeIdentity.notThisService,
          reason: service.title,
        );
      }
    });

    test('TrueNAS and Dockge are proven by their handshake', () {
      for (final body in [null, _page, const <String, Object?>{}]) {
        expect(
          identifyProbeAnswer(ServiceKey.truenas, body),
          ProbeIdentity.matches,
        );
        expect(
          identifyProbeAnswer(ServiceKey.dockge, body),
          ProbeIdentity.matches,
        );
      }
    });

    test('an arr nobody knows is not this service', () {
      expect(
        identifyProbeAnswer(ServiceKey.radarr, {
          'appName': 'Whisparr',
          'version': '2.0.0',
        }),
        ProbeIdentity.notThisService,
      );
    });

    test('the name compares without case', () {
      expect(
        identifyProbeAnswer(ServiceKey.radarr, {'appName': 'radarr'}),
        ProbeIdentity.matches,
      );
    });
  });

  group('Jellyfin and Emby, which answer the same route', () {
    // Jellyfin forked Emby, and `/System/Info/Public` of the two looks alike.
    // Jellyfin sends a `ProductName` and a single `LocalAddress`; Emby 4.10
    // sends no `ProductName` (the spec of it assumed one) and a
    // `LocalAddresses` list. Both bodies are recorded from real servers.
    final emby = _fixture('emby/system_info_public.json');
    final embyInfo = _fixture('emby/system_info.json');
    final jellyfin = _fixture('jellyfin/system_info_public.json');
  });

  group('Tracearr health, whatever state it is in', () {});

  group('WrongServiceAnswer', () {
    test('another service says who answered where', () {
      final error = WrongServiceAnswer(
        ServiceKey.radarr,
        const ProbeIdentity.otherService(ServiceKey.sonarr),
        url: 'http://nas.home.arpa:7878',
      );

      expect(error.reason, ServiceFailureReason.notFound);
      expect(classifyConnectionFailure(error), ServiceFailureReason.notFound);
      expect(
        connectionFailureDetail(error),
        'Sonarr answered at nas.home.arpa:7878, not Radarr.',
      );
      expect(failureRemedy(ServiceFailureReason.notFound), 'Check the address');
    });

    test('something else, with the path hint when the address has none', () {
      expect(
        WrongServiceAnswer(
          ServiceKey.radarr,
          ProbeIdentity.notThisService,
          url: 'https://radarr.example.com',
        ).failureDetail,
        "Something answered at radarr.example.com, but it isn't Radarr.\n"
        'If Radarr sits under a path, add it: https://radarr.example.com/radarr',
      );
      expect(
        WrongServiceAnswer(
          ServiceKey.sonarr,
          ProbeIdentity.notThisService,
          url: 'https://example.com/',
        ).failureDetail,
        "Something answered at example.com, but it isn't Sonarr.\n"
        'If Sonarr sits under a path, add it: https://example.com/sonarr',
      );
    });

    test('no path hint when the address already has a path', () {
      expect(
        WrongServiceAnswer(
          ServiceKey.radarr,
          ProbeIdentity.notThisService,
          url: 'https://example.com/movies',
        ).failureDetail,
        "Something answered at example.com, but it isn't Radarr.",
      );
    });

    test('prints no address', () {
      final error = WrongServiceAnswer(
        ServiceKey.radarr,
        ProbeIdentity.notThisService,
        url: 'https://radarr.example.com',
      );

      expect(error.toString(), isNot(contains('example.com')));
    });
  });

  group('a web page in the service\'s place', () {
    test('reads the same wherever it met the request', () {
      final page = UnexpectedAnswer(
        status: 200,
        body: _page,
        host: 'radarr.example.com',
        baseUrl: 'https://radarr.example.com',
      );

      expect(page.reason, ServiceFailureReason.notFound);
      expect(
        webPageSentence(ServiceKey.radarr, page),
        'A web page answered at radarr.example.com instead of Radarr.\n'
        'If Radarr sits under a path, add it: https://radarr.example.com/radarr',
      );
    });

    test('no path hint when the address has a path', () {
      final page = UnexpectedAnswer(
        body: _page,
        host: 'example.com',
        baseUrl: 'https://example.com/movies',
      );

      expect(
        webPageSentence(ServiceKey.radarr, page),
        'A web page answered at example.com instead of Radarr.',
      );
    });

    test('a page read as text is the same answer, not "isn\'t Radarr"', () {
      // qBittorrent and SABnzbd ask for no JSON, so a page reaches their
      // identity check as text.
      expect(
        () => requireProbeIdentity(
          ServiceKey.qbittorrent,
          _page,
          url: 'http://nas.home.arpa:8080',
        ),
        throwsA(
          isA<UnexpectedAnswer>()
              .having((e) => e.isWebPage, 'isWebPage', isTrue)
              .having((e) => e.host, 'host', 'nas.home.arpa:8080'),
        ),
      );
      // Text that is not a page is still not qBittorrent.
      expect(
        () => requireProbeIdentity(
          ServiceKey.qbittorrent,
          'Welcome',
          url: 'http://nas.home.arpa:8080',
        ),
        throwsA(isA<WrongServiceAnswer>()),
      );
    });

    test('a body that is not a page and does not decode stays unreadable', () {
      expect(
        UnexpectedAnswer(status: 200, body: '{"records": [').reason,
        ServiceFailureReason.invalidResponse,
      );
    });
  });
}
