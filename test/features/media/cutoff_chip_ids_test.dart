import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';

import '../../test_helpers/fake_api_client.dart';

/// The "Cutoff unmet" chips read `wanted/cutoff` for a set of ids and nothing
/// else, so what they ask the server to embed in every record is pure weight:
/// Sonarr's series and episode file in each episode, Lidarr's artist in each
/// album.
void main() {
  late FakeApiClient client;

  setUp(() => client = FakeApiClient());

  test('the Sonarr chip folds the episodes into series ids and asks for no '
      'embed', () async {
    client.getResponseData = {
      'records': [
        {'id': 1, 'seriesId': 7},
        {'id': 2, 'seriesId': 7},
        {'id': 3, 'seriesId': 9},
      ],
      'totalRecords': 3,
    };
    final container = ProviderContainer(
      overrides: [
        sonarrServiceProvider.overrideWith((_) => SonarrService(client)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sonarrCutoffUnmetSeriesIdsProvider, (_, _) {});

    final ids = await container.read(sonarrCutoffUnmetSeriesIdsProvider.future);

    expect(ids, {7, 9});
    expect(client.lastGetPath, '/api/v3/wanted/cutoff');
    expect(client.lastGetQueryParameters, containsPair('includeSeries', false));
    expect(
      client.lastGetQueryParameters,
      containsPair('includeEpisodeFile', false),
    );
  });
}
