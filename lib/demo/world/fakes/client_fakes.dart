/// The four download clients on the fake network: qBittorrent, Transmission,
/// SABnzbd and NZBGet.
///
/// Rows come from `WorldDownloads`, so a torrent here and its row in the
/// Radarr or Sonarr queue share the download id the Dashboard joins on.
library;

import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/service_fakes.dart';
import 'package:cupola/demo/world/world.dart';

List<WorldDownload> _rowsOf(ServerContext c, String client) => [
  for (final d in c.downloads)
    if (d.client == client) d,
];

// === qBittorrent ===========================================================

/// qBittorrent's WebUI: form login, `SID` cookie, then the v2 API.
///
/// A refused sign-in is `200 Fails.` on the login route: the ≤ 5.0 spelling
/// the client is written against, and `403` everywhere else, which is what an
/// unauthenticated WebUI answers.
class QbittorrentFake extends ServiceFake {
  const QbittorrentFake();

  static const _login = '/api/v2/auth/login';

  @override
  bool isWrite(NetworkRequest request) =>
      request.method == 'POST' && request.path != _login;

  @override
  NetworkReply refuseKey(NetworkRequest request) => request.path == _login
      ? NetworkReply.text('Fails.')
      : NetworkReply.text('Forbidden', status: 403);

  @override
  NetworkReply refuseWrite(NetworkRequest request) =>
      NetworkReply.text('Forbidden', status: 403);

  static String _state(WorldDownload d) => switch (d.state) {
    DownloadState.downloading => 'downloading',
    DownloadState.stuck => 'stalledDL',
    DownloadState.queued => 'queuedDL',
    DownloadState.importBlocked || DownloadState.seeding => 'stalledUP',
    DownloadState.stopped => 'stoppedUP',
    DownloadState.failed => 'error',
    DownloadState.missingFiles => 'missingFiles',
    DownloadState.heldByClient || DownloadState.paused => 'stoppedDL',
  };

  static JsonMap torrent(ServerContext c, WorldDownload d) {
    final now = c.now.millisecondsSinceEpoch ~/ 1000;
    final stuck = d.state == DownloadState.stuck;
    return {
      'hash': d.id.toLowerCase(),
      'name': d.release,
      'state': _state(d),
      'progress': d.progress,
      'size': d.size,
      'total_size': d.size,
      'amount_left': d.sizeLeft,
      'downloaded': d.size - d.sizeLeft,
      'completed': d.size - d.sizeLeft,
      'uploaded': d.progress == 1 ? d.size * 2 : 0,
      'dlspeed': d.speed,
      'upspeed': d.state == DownloadState.seeding ? 120000 : 0,
      'eta': d.eta?.inSeconds ?? 8640000,
      'ratio': d.release.startsWith('Sintel') ? 2.4 : 1.1,
      'category': switch (d.arr) {
        WorldIds.radarr || WorldIds.radarr4k => 'radarr',
        WorldIds.sonarr || WorldIds.sonarrAnime => 'tv-sonarr',
        _ => '',
      },
      'tags': '',
      'save_path': '/mnt/tank/downloads/',
      'content_path': '/mnt/tank/downloads/${d.release}',
      'added_on': now - 3 * 3600,
      'completion_on': d.progress == 1 ? now - 3600 : -1,
      'last_activity': stuck ? now - 3 * 3600 : now - 5,
      'num_seeds': d.peers ?? (stuck ? 0 : 12),
      'num_complete': stuck ? 0 : 40,
      'num_leechs': 3,
      'num_incomplete': 5,
      'priority': 1,
      'force_start': false,
      'tracker': 'https://tracker.example.net/announce',
      'magnet_uri': 'magnet:?xt=urn:btih:${d.id.toLowerCase()}',
    };
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final rows = _rowsOf(c, 'qbittorrent');
    switch ((r.method, r.path)) {
      case ('POST', _login):
        return NetworkReply.text(
          'Ok.',
          headers: {
            'set-cookie': ['SID=world-session; HttpOnly; path=/'],
          },
        );
      case ('GET', '/api/v2/app/version'):
        return NetworkReply.text('v4.6.7');
      case ('GET', '/api/v2/app/webapiVersion'):
        return NetworkReply.text('2.9.3');
      case ('GET', '/api/v2/app/preferences'):
        return NetworkReply.json({
          'dl_limit': 0,
          'up_limit': 0,
          'alt_dl_limit': 5 * 1024 * 1024,
          'alt_up_limit': 1024 * 1024,
          'save_path': '/mnt/tank/downloads/',
        });
      case ('GET', '/api/v2/torrents/info'):
        final hashes = r.query['hashes']?.split('|').toSet();
        return NetworkReply.json([
          for (final d in rows)
            if (hashes == null || hashes.contains(d.id.toLowerCase()))
              torrent(c, d),
        ]);
      case ('GET', '/api/v2/transfer/info'):
        return NetworkReply.json({
          'dl_info_speed': rows.fold<int>(0, (sum, d) => sum + d.speed),
          'up_info_speed': 1153433,
          'dl_info_data': 42000000000,
          'up_info_data': 77000000000,
          'dl_rate_limit': 0,
          'up_rate_limit': 0,
          'connection_status': 'connected',
          'dht_nodes': 380,
        });
      case ('GET', '/api/v2/transfer/speedLimitsMode'):
        return NetworkReply.text('0');
      case ('GET', '/api/v2/sync/maindata'):
        return NetworkReply.json({
          'rid': 1,
          'full_update': true,
          'torrents': {for (final d in rows) d.id.toLowerCase(): torrent(c, d)},
          // What a real server_state carries: the session's figures under the
          // same keys `/transfer/info` uses, and the ones it leaves out.
          'server_state': {
            'dl_info_speed': rows.fold<int>(0, (sum, d) => sum + d.speed),
            'up_info_speed': 1153433,
            'dl_info_data': 42000000000,
            'up_info_data': 77000000000,
            'dl_rate_limit': 0,
            'up_rate_limit': 0,
            'dht_nodes': 380,
            'free_space_on_disk': 13634000000000,
            'alltime_dl': 9000000000000,
            'alltime_ul': 16560000000000,
            'global_ratio': '1.84',
            'use_alt_speed_limits': false,
            'connection_status': 'connected',
          },
        });
      case ('GET', '/api/v2/torrents/properties'):
        return NetworkReply.json({
          'save_path': '/mnt/tank/downloads/',
          'total_size': 0,
          'seeds': 0,
          'peers': 0,
        });
      case ('GET', '/api/v2/torrents/files'):
      case ('GET', '/api/v2/torrents/trackers'):
        return NetworkReply.json(const <Object?>[]);
      case ('GET', '/api/v2/rss/items'):
        return NetworkReply.json(_rssItems(c, withData: r.query['withData']));
      case ('GET', '/api/v2/rss/rules'):
        return NetworkReply.json(_rssRules(c));
      case ('GET', '/api/v2/torrents/categories'):
        return NetworkReply.json({
          'radarr': {'name': 'radarr', 'savePath': ''},
          'tv-sonarr': {'name': 'tv-sonarr', 'savePath': ''},
        });
      case ('GET', '/api/v2/torrents/tags'):
        return NetworkReply.json(const <Object?>[]);
    }
    if (r.method == 'POST') {
      _write(r, c, rows);
      return NetworkReply.text('Ok.');
    }
    return null;
  }

  static const _rssFeedUrl = 'https://feeds.example.net/open-movies.xml';

  /// The one feed the household follows, as `rss/items` sends it: the feed
  /// is a leaf with its `url`, and with `withData=true` its articles, one
  /// of them already read. Without `withData` a leaf is the bare URL, which
  /// is what an older WebUI sends and what the app reads without a count.
  static JsonMap _rssItems(ServerContext c, {String? withData}) {
    if (withData != 'true') return {'Open Movies': _rssFeedUrl};
    JsonMap article(
      String id,
      String title,
      Duration age, {
      bool read = false,
    }) => {
      'id': id,
      'title': title,
      'date': c.ago(age),
      'description': '$title, released by the Open Movies feed.',
      'torrentURL': 'https://feeds.example.net/torrent/$id.torrent',
      'isRead': read,
    };
    return {
      'Open Movies': {
        'uid': '{6b1f3a52-0c7e-4d0b-9a55-2f0c4a7e91d3}',
        'url': _rssFeedUrl,
        'title': 'Open Movies',
        'lastBuildDate': c.ago(const Duration(minutes: 40)),
        'isLoading': false,
        'hasError': false,
        'articles': [
          article(
            'tears-of-steel-1080p',
            'Tears.of.Steel.2012.1080p.BluRay',
            const Duration(hours: 5),
          ),
          article(
            'spring-1080p',
            'Spring.2014.1080p.BluRay',
            const Duration(days: 1, hours: 2),
            read: true,
          ),
          article(
            'charge-1080p',
            'Charge.2022.1080p.WEB',
            const Duration(days: 2, hours: 7),
            read: true,
          ),
          article(
            'coffee-run-720p',
            'Coffee.Run.2020.720p.WEB',
            const Duration(days: 3),
          ),
        ],
      },
    };
  }

  /// The rule that sends what the feed carries at 1080p to Radarr's
  /// category, as `rss/rules` sends it.
  static JsonMap _rssRules(ServerContext c) => {
    'Open Movies 1080p': {
      'enabled': true,
      'mustContain': '1080p',
      'mustNotContain': 'CAM|HDTS|TELESYNC',
      'useRegex': true,
      'episodeFilter': '',
      'smartFilter': false,
      'previouslyMatchedEpisodes': const <Object?>[],
      'affectedFeeds': const [_rssFeedUrl],
      'ignoreDays': 0,
      'lastMatch': c.ago(const Duration(days: 1, hours: 2)),
      'addPaused': null,
      'assignedCategory': 'radarr',
      'savePath': '',
    },
  };

  /// What a write does to a living world: pause, resume, delete. The rest
  /// (tags, limits, a recheck) is answered and changes nothing the world
  /// draws.
  static void _write(
    NetworkRequest r,
    ServerContext c,
    List<WorldDownload> rows,
  ) {
    final life = c.life;
    if (life == null) return;
    final named = r.form['hashes'] ?? '';
    final hashes = named == 'all'
        ? [for (final d in rows) d.id]
        : named.split('|').where((h) => h.isNotEmpty).toList();
    final act = switch (r.path) {
      '/api/v2/torrents/stop' || '/api/v2/torrents/pause' => life.pause,
      '/api/v2/torrents/start' || '/api/v2/torrents/resume' => life.resume,
      '/api/v2/torrents/delete' => life.remove,
      _ => null,
    };
    if (act == null) return;
    hashes.forEach(act);
  }
}

// === Transmission ==========================================================

// === SABnzbd ===============================================================

// === NZBGet (World B) ======================================================
