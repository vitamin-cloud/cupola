import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_health.dart';

/// An \*arr's failing health checks in the app's words, and the same check on
/// several \*arrs as one fault.
void main() {
  test('names are said as a sentence lists them', () {
    expect(namesSaid(const ['Radarr']), 'Radarr');
    expect(namesSaid(const ['Radarr', 'Sonarr']), 'Radarr and Sonarr');
    expect(
      namesSaid(const ['Radarr', 'Sonarr', 'Lidarr']),
      'Radarr, Sonarr and Lidarr',
    );
  });

  test('a known check in the app\'s words, naming no arr', () {
    expect(arrHealthWords('IndexerRssCheck'), (
      headline: 'No indexer is watching for new releases',
      explanation:
          "New releases aren't grabbed on their own until an indexer has RSS "
          'sync on.',
    ));
    expect(arrHealthWords('SomeNewCheck'), isNull);
  });
}
