import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/set_up_next.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Set up next names what the stack lacks, once, in the order of what it
/// adds.
void main() {
  List<String> titles(Set<ServiceKey> setUp) => [
    for (final suggestion in setUpNextOf(setUp.contains)) suggestion.title,
  ];

  test('no Seerr comes first: it adds the most', () {
    expect(
      titles({ServiceKey.radarr, ServiceKey.qbittorrent}).first,
      'Set up Seerr',
    );
  });

  test('Plex stands for Jellyfin, any client for the four', () {
    final names = titles({
      ServiceKey.seerr,
      ServiceKey.radarr,
      ServiceKey.sonarr,
    });
    expect(names, ['Set up Bazarr']);
  });

  test('nothing it knows of missing: no module', () {
    expect(
      setUpNextOf(
        {
          ServiceKey.seerr,
          ServiceKey.jellyfin,
          ServiceKey.radarr,
          ServiceKey.sonarr,
        }.contains,
      ),
      isEmpty,
    );
  });

  test('the module names three, then All services', () {
    expect(setUpNextLimit, 3);
    expect(titles(const {}).length, greaterThan(setUpNextLimit));
  });
}
