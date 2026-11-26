import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/real_network.dart';

KnockAnswer _answer(
  int status,
  String body, {
  Map<String, List<String>> headers = const {},
}) => (status: status, headers: headers, body: body);

bool _answers(ServiceKey service, KnockAnswer answer) =>
    knockPlanOf(service, 'http://nas.lan:1234')!.answers(answer);

void main() {
  useRealNetwork();

  group('what proves the service, as the lab answers', () {
    test('qBittorrent: its version, or Forbidden to a caller signed out', () {
      expect(_answers(ServiceKey.qbittorrent, _answer(200, 'v5.0.4')), isTrue);
      expect(
        _answers(ServiceKey.qbittorrent, _answer(403, 'Forbidden')),
        isTrue,
      );
      expect(
        _answers(ServiceKey.qbittorrent, _answer(403, '<html>no</html>')),
        isFalse,
      );
    });

    test('Dockge: its own page names it', () {
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(200, '<!DOCTYPE html><html><head><title>Dockge</title>'),
        ),
        isTrue,
      );
    });

    test('Dockge: another Socket.IO server is not Dockge', () {
      // Tracearr opens the same polling session without signing in, and its
      // page names Tracearr: neither answer may read as Dockge.
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(
            200,
            '0{"sid":"fog1","upgrades":["websocket"],"pingInterval":25000}',
          ),
        ),
        isFalse,
      );
      expect(
        _answers(
          ServiceKey.dockge,
          _answer(200, '<!DOCTYPE html><html><head><title>Tracearr</title>'),
        ),
        isFalse,
      );
    });

    test('TrueNAS is knocked by opening a connection to its port', () {
      expect(knockPlanOf(ServiceKey.truenas, 'https://nas.lan'), isNull);
    });
  });

  group('who may receive the access layer after a challenge', () {
    test('a host TLS has authenticated', () {
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('https://radarr.example.com')),
        isTrue,
      );
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('https://192.168.1.10:7878')),
        isTrue,
      );
    });

    test('never a cleartext address, at home or away', () {
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('http://192.168.1.10:7878')),
        isFalse,
      );
      expect(
        mayCarryAccessAfterChallenge(Uri.parse('http://radarr.example.com')),
        isFalse,
      );
    });
  });

  group('a knock on a server', () {
    late HttpServer server;
    late List<HttpHeaders> received;
    late FutureOr<void> Function(HttpRequest request) handle;

    setUp(() async {
      received = [];
      handle = (request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"status": "OK"}');
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received.add(request.headers);
        await handle(request);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
    });

    String url() => 'http://127.0.0.1:${server.port}';

    Future<bool> knock({
      ConnectionAccess access = const NoAccess(),
      Duration timeout = const Duration(seconds: 2),
    }) => knockAt(
      ServiceKey.radarr,
      (url: url(), access: access, pin: null),
      timeout: timeout,
      hostReach: (_) async => false,
    );

    test('answered as the service is true', () async {
      expect(await knock(), isTrue);
    });

    test(
      'sends no key and no access to a server that answered directly',
      () async {
        await knock(
          access: const CustomHeaders([
            (name: 'X-Proxy-Key', value: 'gateway-value'),
          ]),
        );

        final headers = received.single;
        expect(headers.value('x-api-key'), isNull);
        expect(headers.value('authorization'), isNull);
        expect(headers.value('x-proxy-key'), isNull);
      },
    );

    test(
      'a challenge over http never gets the access: the host is unproved',
      () async {
        var calls = 0;
        handle = (request) {
          calls++;
          if (request.headers.value('x-proxy-key') == null) {
            request.response
              ..statusCode = 401
              ..headers.set('www-authenticate', 'Basic realm="gateway"');
            return;
          }
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"status": "OK"}');
        };

        expect(
          await knock(
            access: const CustomHeaders([
              (name: 'X-Proxy-Key', value: 'gateway-value'),
            ]),
          ),
          isFalse,
        );
        expect(calls, 1);
        expect(received.single.value('x-proxy-key'), isNull);
      },
    );

    test('a redirect is not the service', () async {
      handle = (request) {
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://portal.example/login');
      };

      expect(await knock(), isFalse);
    });

    test('a foreign redirect never gets the access on a retry', () async {
      var calls = 0;
      handle = (request) {
        calls++;
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://portal.example/login');
      };

      expect(
        await knock(
          access: const CustomHeaders([
            (name: 'X-Proxy-Key', value: 'gateway-value'),
          ]),
        ),
        isFalse,
      );
      expect(calls, 1);
    });

    test('a server that never answers is false within the time', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      handle = (_) => never.future;

      final watch = Stopwatch()..start();
      expect(await knock(timeout: const Duration(milliseconds: 300)), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('nothing listening is false', () async {
      final port = server.port;
      await server.close(force: true);

      expect(
        await knockAt(
          ServiceKey.radarr,
          (url: 'http://127.0.0.1:$port', access: const NoAccess(), pin: null),
          timeout: const Duration(seconds: 1),
          hostReach: (_) async => false,
        ),
        isFalse,
      );
    });
  });
}
