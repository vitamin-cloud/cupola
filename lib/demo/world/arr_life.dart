import 'package:cupola/demo/world/fakes/arr_fakes.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/world.dart';
import 'package:cupola/demo/world/world_life.dart';

/// One film on one Radarr, as the living world keeps it.
class LiveMovie {
  LiveMovie({
    required this.id,
    required this.title,
    required this.hasFile,
    required this.added,
    this.arrived,
  });

  final int id;
  final WorldTitle title;
  bool hasFile;
  bool monitored = true;
  final DateTime added;

  /// When its file was imported, or null for none.
  DateTime? arrived;

  /// When it arrived in the demo, or null for a film the world already held.
  DateTime? arrivedLive;
}

/// One series on one Sonarr, as the living world keeps it.
class LiveSeries {
  LiveSeries({
    required this.id,
    required this.title,
    required this.added,
    this.seeded = false,
  });

  final int id;

  /// One of the world's own series, whose episodes the world writes; false
  /// for one added in the demo, which holds only what arrived.
  final bool seeded;
  final WorldTitle title;
  final DateTime added;
  bool monitored = true;

  /// Seasons whose monitoring changed, by number.
  final Map<int, bool> seasonsMonitored = {};

  /// Episodes whose monitoring changed, by episode id.
  final Map<int, bool> episodesMonitored = {};

  /// Episodes that arrived in the demo, as `(season, episode)`.
  final Set<(int, int)> arrivedEpisodes = {};

  /// Seasons whose whole pack arrived, by number: a series added in the demo
  /// that the world holds no episodes of.
  final Set<int> arrivedSeasons = {};

  /// When the last of it arrived.
  DateTime? arrived;
}

/// One artist added to a Lidarr in the demo. The world's own artist is
/// `LidarrFake`'s; only what the demo adds is kept here.
class LiveArtist {
  LiveArtist({
    required this.id,
    required this.name,
    required this.foreignArtistId,
    required this.added,
    this.monitored = true,
    this.readsAlbums = true,
  });

  final int id;
  final String name;
  final String foreignArtistId;
  final DateTime added;
  bool monitored;

  /// Whether Lidarr reads the artist's albums after the add: not for an
  /// artist that came in with one album, whose only album is that one.
  final bool readsAlbums;
}

/// What the demo changed on an artist of a Lidarr by the editor: only what
/// was set, the rest is the artist's own. Kept by id, so it holds for the
/// world's artists and the shelf's as it does for those the demo added.
class LiveArtistEdit {
  bool? monitored;
  String? monitorNewItems;
  int? qualityProfileId;
  int? metadataProfileId;
}

/// One album added to a Lidarr in the demo, under the world's artist (id 1)
/// or one the demo added.
class LiveAlbum {
  LiveAlbum({
    required this.id,
    required this.artistId,
    required this.title,
    required this.foreignAlbumId,
    required this.albumType,
    required this.releaseDate,
    this.monitored = true,
  });

  final int id;
  final int artistId;
  final String title;
  final String foreignAlbumId;
  final String albumType;
  final String releaseDate;
  bool monitored;
}

/// The arrs' libraries once the world lives: a film added, monitored or let
/// go, a search that grabs, a download that arrives.
///
/// A library is read from the world's own list the first time it is asked
/// for, and kept from then on.
class ArrLife {
  ArrLife(this._life, this._network) {
    _life.onFinished(_arrive);
  }

  final WorldLife _life;
  final ProfileNetwork _network;

  final Map<String, List<LiveMovie>> _movies = {};
  final Map<String, List<LiveSeries>> _series = {};
  final Map<String, List<LiveArtist>> _artists = {};
  final Map<String, Map<int, LiveArtistEdit>> _artistEdits = {};
  final Map<String, Set<int>> _removedArtists = {};
  final Map<String, List<LiveAlbum>> _albums = {};
  final Map<String, Set<int>> _removedAuthors = {};
  final Map<String, Map<int, bool>> _authorMonitored = {};
  int _grabs = 0;

  /// How long a grab takes to come down, so a title asked for arrives in
  /// about a minute and a half (the demo's pace, `DM-5`).
  static const grabTime = Duration(seconds: 75);

  DateTime get _now => _network.currentTime;

  // === Radarr ==============================================================

  /// Radarr [serverId]'s films.
  List<LiveMovie> movies(String serverId) => _movies.putIfAbsent(serverId, () {
    final seed = _network.server(serverId).is4k
        ? RadarrFake.library4k
        : RadarrFake.libraryHd;
    return [
      for (final (id, title, hasFile, ago) in seed)
        LiveMovie(
          id: id,
          title: title,
          hasFile: hasFile,
          added: _now.subtract(ago),
          arrived: hasFile ? _now.subtract(ago) : null,
        ),
    ];
  });

  LiveMovie? movie(String serverId, int id) =>
      movies(serverId).where((m) => m.id == id).firstOrNull;

  LiveMovie? movieOf(String serverId, WorldTitle title) =>
      movies(serverId).where((m) => m.title == title).firstOrNull;

  /// Adds [title] to Radarr [serverId], or finds it there; searches for it
  /// at once when [search] says so.
  LiveMovie addMovie(
    String serverId,
    WorldTitle title, {
    bool monitored = true,
    bool search = false,
  }) {
    final held = movieOf(serverId, title);
    final movie =
        held ??
        LiveMovie(
          id:
              movies(
                serverId,
              ).fold<int>(0, (top, m) => m.id > top ? m.id : top) +
              1,
          title: title,
          hasFile: false,
          added: _now,
        );
    if (held == null) movies(serverId).add(movie);
    movie.monitored = monitored;
    if (search) searchMovie(serverId, movie.id);
    return movie;
  }

  /// Radarr [serverId] lets film [id] go (its files with it, as far as the
  /// world can tell).
  void deleteMovie(String serverId, int id) =>
      movies(serverId).removeWhere((m) => m.id == id);

  /// A search for film [id]: a missing film with no download under way gets
  /// one.
  void searchMovie(String serverId, int id, {String? release}) {
    final movie = this.movie(serverId, id);
    if (movie == null || movie.hasFile || _downloading(serverId, movie.title)) {
      return;
    }
    final is4k = _network.server(serverId).is4k;
    _grab(
      arr: serverId,
      title: movie.title,
      release: release ?? releaseName(movie.title, is4k: is4k),
      usenet: is4k,
      size: is4k ? 8800000000 : 2200000000,
    );
  }

  // === Readarr =============================================================

  /// The authors removed from Readarr [serverId] in the demo. The world's own
  /// author is Readarr's, so what is kept here is what was done to it.
  Set<int> removedAuthors(String serverId) =>
      _removedAuthors.putIfAbsent(serverId, () => {});

  /// Whether the demo set author [id] monitored or not, or null for one it has
  /// left as it was.
  bool? authorMonitored(String serverId, int id) =>
      _authorMonitored[serverId]?[id];

  void monitorAuthor(String serverId, int id, {required bool monitored}) =>
      _authorMonitored.putIfAbsent(serverId, () => {})[id] = monitored;

  // === Lidarr ==============================================================

  /// The artists added to Lidarr [serverId] in the demo, after the world's
  /// own (id 1).
  List<LiveArtist> artists(String serverId) =>
      _artists.putIfAbsent(serverId, () => []);

  LiveArtist? artist(String serverId, int id) =>
      artists(serverId).where((a) => a.id == id).firstOrNull;

  /// What the demo changed on artist [id] of Lidarr [serverId], or null for an
  /// artist it has left as it was.
  LiveArtistEdit? artistEdit(String serverId, int id) =>
      _artistEdits[serverId]?[id];

  /// Sets what is given of artist [id]'s settings on Lidarr [serverId].
  void editArtist(
    String serverId,
    int id, {
    bool? monitored,
    String? monitorNewItems,
    int? qualityProfileId,
    int? metadataProfileId,
  }) {
    final edit = (_artistEdits.putIfAbsent(serverId, () => {})[id] ??=
        LiveArtistEdit());
    if (monitored != null) edit.monitored = monitored;
    if (monitorNewItems != null) edit.monitorNewItems = monitorNewItems;
    if (qualityProfileId != null) edit.qualityProfileId = qualityProfileId;
    if (metadataProfileId != null) edit.metadataProfileId = metadataProfileId;
  }

  /// The artists removed from Lidarr [serverId] in the demo.
  Set<int> removedArtists(String serverId) =>
      _removedArtists.putIfAbsent(serverId, () => {});

  /// Adds the artist [name] to Lidarr [serverId], or finds it there.
  LiveArtist addArtist(
    String serverId,
    String name, {
    required String foreignArtistId,
    bool monitored = true,
    bool readsAlbums = true,
  }) {
    final held = artists(
      serverId,
    ).where((a) => a.foreignArtistId == foreignArtistId).firstOrNull;
    if (held != null) return held;
    final top = artists(
      serverId,
    ).fold<int>(1, (top, a) => a.id > top ? a.id : top);
    final artist = LiveArtist(
      id: top + 1,
      name: name,
      foreignArtistId: foreignArtistId,
      added: _now,
      monitored: monitored,
      readsAlbums: readsAlbums,
    );
    artists(serverId).add(artist);
    return artist;
  }

  /// The albums added to Lidarr [serverId] in the demo, after the world's own
  /// (ids 1 to 4), from id 200.
  List<LiveAlbum> albums(String serverId) =>
      _albums.putIfAbsent(serverId, () => []);

  /// Adds the album [title] under [artistId] to Lidarr [serverId], or finds
  /// it there.
  LiveAlbum addAlbum(
    String serverId, {
    required int artistId,
    required String title,
    required String foreignAlbumId,
    required String albumType,
    required String releaseDate,
  }) {
    final held = albums(
      serverId,
    ).where((a) => a.foreignAlbumId == foreignAlbumId).firstOrNull;
    if (held != null) return held;
    final top = albums(
      serverId,
    ).fold<int>(199, (top, a) => a.id > top ? a.id : top);
    final album = LiveAlbum(
      id: top + 1,
      artistId: artistId,
      title: title,
      foreignAlbumId: foreignAlbumId,
      albumType: albumType,
      releaseDate: releaseDate,
    );
    albums(serverId).add(album);
    return album;
  }

  // === Sonarr ==============================================================

  /// Sonarr [serverId]'s series.
  List<LiveSeries> series(String serverId) => _series.putIfAbsent(serverId, () {
    final anime = _network
        .server(serverId)
        .label
        .toLowerCase()
        .contains('anime');
    return [
      for (final (id, title)
          in anime ? SonarrFake.libraryAnime : SonarrFake.libraryMain)
        LiveSeries(
          id: id,
          title: title,
          added: _now.subtract(const Duration(days: 300)),
          seeded: true,
        ),
    ];
  });

  LiveSeries? oneSeries(String serverId, int id) =>
      series(serverId).where((s) => s.id == id).firstOrNull;

  LiveSeries? seriesOf(String serverId, WorldTitle title) =>
      series(serverId).where((s) => s.title == title).firstOrNull;

  /// Adds [title] to Sonarr [serverId], or finds it there; searches for its
  /// first season at once when [search] says so.
  LiveSeries addSeries(
    String serverId,
    WorldTitle title, {
    bool monitored = true,
    bool search = false,
  }) {
    final held = seriesOf(serverId, title);
    final added =
        held ??
        LiveSeries(
          id:
              series(
                serverId,
              ).fold<int>(0, (top, s) => s.id > top ? s.id : top) +
              1,
          title: title,
          added: _now,
        );
    if (held == null) series(serverId).add(added);
    added.monitored = monitored;
    if (search) searchSeason(serverId, added.id, 1);
    return added;
  }

  void deleteSeries(String serverId, int id) =>
      series(serverId).removeWhere((s) => s.id == id);

  /// A search for season [season] of series [id]: a season pack, unless the
  /// world already holds it or is fetching it.
  void searchSeason(String serverId, int id, int season) {
    final one = oneSeries(serverId, id);
    if (one == null ||
        one.arrivedSeasons.contains(season) ||
        _downloading(serverId, one.title)) {
      return;
    }
    _grab(
      arr: serverId,
      title: one.title,
      release:
          '${_dotted(one.title)}.S${season.toString().padLeft(2, '0')}'
          '.1080p.WEB-DL.x264-WORLD',
      season: season,
      size: 6400000000,
    );
  }

  /// A search for one episode, by season and number.
  void searchEpisode(String serverId, int id, int season, int episode) {
    final one = oneSeries(serverId, id);
    if (one == null || one.arrivedEpisodes.contains((season, episode))) return;
    final code =
        'S${season.toString().padLeft(2, '0')}'
        'E${episode.toString().padLeft(2, '0')}';
    final busy = _life.downloads.any(
      (d) =>
          d.arr == serverId &&
          d.title == one.title &&
          d.season == season &&
          d.episode == episode,
    );
    if (busy) return;
    _grab(
      arr: serverId,
      title: one.title,
      release: '${_dotted(one.title)}.$code.1080p.WEB-DL.x264-WORLD',
      season: season,
      episode: episode,
      size: 1200000000,
    );
  }

  // === Grabs and arrivals ==================================================

  /// The name a release of [title] goes by.
  static String releaseName(WorldTitle title, {required bool is4k}) =>
      '${_dotted(title)}.${title.year}.'
      '${is4k ? '2160p.UHD.BluRay.x265' : '1080p.WEB-DL.x264'}-WORLD';

  static String _dotted(WorldTitle title) =>
      title.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '.');

  bool _downloading(String serverId, WorldTitle title) =>
      _life.downloads.any((d) => d.arr == serverId && d.title == title);

  void _grab({
    required String arr,
    required WorldTitle title,
    required String release,
    required int size,
    bool usenet = false,
    int? season,
    int? episode,
  }) {
    _grabs++;
    _life.add(
      WorldDownload(
        id: 'de' * 4 + _grabs.toRadixString(16).padLeft(32, '0'),
        release: release,
        client: 'qbittorrent',
        state: DownloadState.downloading,
        progress: 0,
        size: size,
        arr: arr,
        title: title,
        season: season,
        episode: episode,
        speed: size ~/ grabTime.inSeconds,
        eta: grabTime,
      ),
    );
  }

  /// An import: download [id] leaves its arr's queue and its title is on
  /// disk. A torrent stays with its client and seeds.
  void import(String id) {
    final download = _life.byId(id);
    if (download == null) return;
    _life.settle(download.id);
    _arrive(download, _now);
  }

  void _arrive(WorldDownload d, DateTime at) {
    final arr = d.arr;
    final title = d.title;
    if (arr == null || title == null) return;
    final service = _network.server(arr).service.name;
    if (service == 'radarr') {
      final movie = movieOf(arr, title) ?? addMovie(arr, title);
      movie
        ..hasFile = true
        ..arrived = at
        ..arrivedLive = at;
    } else if (service == 'sonarr') {
      final one = seriesOf(arr, title) ?? addSeries(arr, title);
      final season = d.season;
      if (season != null && d.episode != null) {
        one.arrivedEpisodes.add((season, d.episode!));
      } else if (season != null) {
        one.arrivedSeasons.add(season);
      }
      one.arrived = at;
    }
  }
}
