import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('Password is offered only where a proxy password can travel', () {
    const signInWithAuthorization = {
    };

    for (final service in ServiceKey.values) {
    }

  });

  group('a custom header named like the service\'s own credential', () {
    test('is offered a move into the credential field', () {
      expect(
        duplicatesCredentialHeader(ServiceKey.radarr, 'x-api-key'),
        isTrue,
      );
      expect(customHeaderNameProblem(ServiceKey.radarr, 'X-Api-Key'), isNull);
      expect(
        credentialHeaderClash(ServiceKey.radarr),
        "Cupola already sends Radarr's key. Move it to the API key field?",
      );
      expect(
        credentialHeaderClash(ServiceKey.plex),
        "Cupola already sends Plex's token. Move it to the Plex token field?",
      );
      expect(
        duplicatesCredentialHeader(ServiceKey.jellyfin, 'X-Emby-Token'),
        isTrue,
      );
    });

  });

  group('a custom header name', () {
    test('never one the transport or the protocol owns', () {
      for (final name in [
        'Host',
        'Content-Length',
        'content-type',
        'Accept',
        'Connection',
        'Transfer-Encoding',
        'Upgrade',
        'Cookie',
        'Sec-WebSocket-Key',
        'sec-websocket-protocol',
      ]) {
        expect(
          customHeaderNameProblem(ServiceKey.radarr, name),
          'Cupola sets this header itself',
          reason: name,
        );
      }
    });


    test('is an RFC 9110 token', () {
      expect(customHeaderNameProblem(ServiceKey.radarr, ''), 'Add a name');
      for (final name in ['X Proxy', 'X:Proxy', 'X-Pröxy', 'X(1)', 'a"b']) {
        expect(
          customHeaderNameProblem(ServiceKey.radarr, name),
          'Use letters, digits and dashes',
          reason: name,
        );
      }
      for (final name in ['X-Proxy-Key', "x!#\$%&'*+.^_`|~1"]) {
        expect(customHeaderNameProblem(ServiceKey.radarr, name), isNull);
      }
    });

    test('appears once', () {
      expect(
        customHeaderNameProblem(
          ServiceKey.radarr,
          'x-proxy',
          earlier: ['X-Proxy'],
        ),
        'This header is already in the list',
      );
    });
  });

  test('a value stays on one line', () {
    expect(customHeaderValueProblem(''), 'Add a value');
    expect(
      customHeaderValueProblem('a\r\nInjected: 1'),
      'Keep the value on one line',
    );
    expect(customHeaderValueProblem('a\nb'), 'Keep the value on one line');
    expect(customHeaderValueProblem('Bearer abc'), isNull);
  });

  test('the headers stay under 8 KB in all', () {
    expect(
      exceedsAccessHeadersLimit([(name: 'X-A', value: 'v' * 8000)]),
      isFalse,
    );
    expect(
      exceedsAccessHeadersLimit([
        (name: 'X-A', value: 'v' * 5000),
        (name: 'X-B', value: 'v' * 5000),
      ]),
      isTrue,
    );
  });

  test('a proxy username', () {
    expect(proxyUsernameProblem(''), 'Add the username');
    expect(proxyUsernameProblem('a:b'), 'A username cannot contain a colon');
    expect(proxyUsernameProblem('matt'), isNull);
  });

}
