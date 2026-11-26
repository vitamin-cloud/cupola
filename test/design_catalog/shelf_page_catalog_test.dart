@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Each catalog picture's light, as the app reads it.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.poster, 'poster'),
    (CatalogArt.backdrop, 'backdrop'),
  ]) {
    final bytes = io.File(
      'design/system/assets/Imagery/$file.jpg',
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: titleLightDecodeSize,
      targetHeight: titleLightDecodeSize,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData())!;
    _lights[url] = await titleLightFromPixels([
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        0xFF000000 |
            rgba.getUint8(i) << 16 |
            rgba.getUint8(i + 1) << 8 |
            rgba.getUint8(i + 2),
    ]);
  }
}

ServiceInstance _connection(ServiceKey service) => ServiceInstance(
  id: service.name,
  service: service,
  label: '',
  url: 'http://nas.home.arpa',
  credential: 'catalog',
);

/// The catalog's TMDB pictures, lit as the app lights them.
Future<TitleLight?> _tmdbLight(String url) async =>
    _lights[url.contains(CatalogArt.tmdbBackdrop)
        ? CatalogArt.backdrop
        : url.contains(CatalogArt.tmdbPoster)
        ? CatalogArt.poster
        : url];

Map<String, Object?> _directed(
  int id,
  String title,
  String date, {
  String type = 'movie',
  int? status,
  bool art = false,
}) => {
  'id': id,
  'mediaType': type,
  if (type == 'tv') 'name': title else 'title': title,
  type == 'tv' ? 'firstAirDate' : 'releaseDate': date,
  'voteAverage': type == 'tv' ? null : 6.6,
  'posterPath': art ? CatalogArt.tmdbPoster : null,
  'job': 'Director',
  'department': 'Directing',
  if (status != null) 'mediaInfo': {'status': status, 'status4k': 5},
};

CatalogScene _personScene(
  String caption, {
  double width = 390,
  double height = 1100,
  double textScale = 1,
  bool seerrSends = true,
  bool paned = false,
}) => CatalogScene(
  caption,
  (_) => paned
      ? MediaPane(
          canGoBack: false,
          onBack: () {},
          child: const PersonPage(personId: 1),
        )
      : const PersonPage(personId: 1),
  width: width,
  height: height,
  textScale: textScale,
  overrides: [
    personDetailProvider.overrideWith(
      (ref, id) async => const PersonDetail(
        id: 1,
        name: 'Ian Hubert',
        knownForDepartment: 'Directing',
        biography:
            'Filmmaker and visual effects artist, known for short films made '
            'with free software and for the lazy tutorials.',
        placeOfBirth: 'Seattle, Washington, USA',
      ),
    ),
    personCreditsProvider.overrideWith(
      (ref, id) async => PersonCombinedCredits.fromJson({
        'crew': [
          _directed(1, 'Dynamo Dream', '2019-02-01', type: 'tv'),
          _directed(2, 'Tears of Steel', '2012-09-26', status: 5, art: true),
          _directed(3, 'Project London', '2011-06-01'),
        ],
      }),
    ),
    seerrNumberingProvider.overrideWith((ref) async => null),
    seerrSendsToProvider.overrideWith((ref, arr) async => seerrSends),
    seriesForProvider.overrideWith((ref, id) async => const []),
    titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
  ],
);

CatalogScene _collectionScene(String caption, {double height = 1700}) =>
    CatalogScene(
      caption,
      (_) => const CollectionPage(collectionId: 1),
      width: 390,
      height: height,
      overrides: [
        collectionDetailProvider.overrideWith(
          (ref, id) async => CollectionDetail(
            id: 1,
            name: 'Blender Open Movies',
            backdropPath: CatalogArt.tmdbBackdrop,
            parts: [
              for (final (id, title, year, status) in const [
                (1, 'Elephants Dream', 2006, 5),
                (2, 'Big Buck Bunny', 2008, 3),
                (3, 'Sintel', 2010, 5),
                (4, 'Tears of Steel', 2012, 5),
                (5, 'Spring', 2019, 5),
                (6, 'Coffee Run', 2020, 5),
                (7, 'Sprite Fright', 2021, 3),
                (8, 'Charge', 2022, 2),
              ])
                MediaPreview(
                  id: id,
                  title: title,
                  mediaType: 'movie',
                  releaseDate: '$year-04-10',
                  voteAverage: 7.4,
                  posterPath: CatalogArt.tmdbPoster,
                  mediaInfo: {'status': status},
                ),
            ],
          ),
        ),
        seerrNumberingProvider.overrideWith((ref) async => null),
        activeRequestsForProvider.overrideWith((ref, id) async => const []),
        titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLights);
  catalogCard(
    'ShelfPage',
    width: 1240,
    overrides: () => settingsScopeOverrides(
      // Seerr and Sonarr for the person and the collection, Radarr not.
      customize: (settings) => [
        _connection(ServiceKey.seerr),
        _connection(ServiceKey.sonarr),
      ].fold(settings, (s, c) => s.copyWithInstance(c)),
    ),
    scenes: [
      _personScene(
        'PersonPage · a director by Seerr\'s credits: the role, one dot per '
        'title, the plus to Sonarr, Request where Seerr sends a movie to its '
        'Radarr, then who they are and where the credits come from',
      ),
      _personScene(
        'PersonPage where nothing set up can add a movie · the plus stays, '
        'dimmed',
        height: 760,
        seerrSends: false,
      ),
      _collectionScene(
        'CollectionPage (ShelfPage.banner) · the still lights the room; how '
        'much is on the server, the strip, the movies in release order',
      ),
      _personScene(
        'PersonPage in a tablet\'s pane, opened from a list · Close, and the '
        'light coming up from the list\'s side',
        width: 660,
        height: 820,
        paned: true,
      ),
      _personScene(
        'PersonPage at twice the reading size',
        height: 2000,
        textScale: catalogTextScale,
      ),
    ],
  );
}
