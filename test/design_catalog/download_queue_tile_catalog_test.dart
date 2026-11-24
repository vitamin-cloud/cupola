@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_tile.dart';

import 'catalog.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

Torrent _torrent(
  String name,
  TorrentState parsed,
  String state, {
  required double progress,
  int size = 8 * _gb,
  int dlSpeed = 0,
  int upSpeed = 0,
  int eta = 8640000,
}) => Torrent(
  hash: name,
  name: name,
  size: size,
  progress: progress,
  state: state,
  parsedState: parsed,
  dlSpeed: dlSpeed,
  upSpeed: upSpeed,
  eta: eta,
  category: 'movies',
  tracker: '',
  tags: const [],
  ratio: 0.4,
  addedOn: 0,
  completed: 0,
  leechers: 3,
  seeders: 12,
);

Widget _column(List<Widget> rows) =>
    Column(mainAxisSize: MainAxisSize.min, children: rows);

void _noop() {}

void main() {
  catalogCard(
    'DownloadQueueTile',
    width: 768,
    scenes: [
      CatalogScene(
        'TorrentTile (qBittorrent) · downloading, stalled, paused, queued, '
        'seeding · blue, amber, neutral, blue, green; no bar when queued or '
        'complete',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.1080p.BluRay.x264-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.63,
              size: 9 * _gb,
              dlSpeed: 25 * _mb,
              upSpeed: 1200 * 1024,
              eta: 720,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.stalled,
              'stalledDL',
              progress: 0.41,
              size: 22 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'The.Cabinet.of.Dr.Caligari.1920.720p.BluRay.x264-GROUP',
              TorrentState.paused,
              'pausedDL',
              progress: 0.22,
              size: 4 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Sherlock.Jr.1924.1080p.BluRay.x264-GROUP',
              TorrentState.queuedDl,
              'queuedDL',
              progress: 0,
              size: 6 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.Score.FLAC-GROUP',
              TorrentState.seeding,
              'uploading',
              progress: 1,
              size: 1300 * _mb,
              upSpeed: 3400 * 1024,
              eta: 7800,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile · a long wait · `2 h 10 min` and `1 d 5 h` left beside a '
        'long name at 390 · the unit stays with its figure, and the name is '
        'what ellipsises',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.REMUX.x265-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.12,
              size: 48 * _gb,
              dlSpeed: 6 * _mb,
              eta: 7800,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'The.Cabinet.of.Dr.Caligari.1920.2160p.UHD.BluRay.REMUX-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.03,
              size: 61 * _gb,
              dlSpeed: 700 * 1024,
              eta: 104400,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile · error draws no bar; fetching metadata and checking '
        'read as in progress',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.1080p.BluRay.x264-GROUP',
              TorrentState.error,
              'error',
              progress: 0.08,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Sherlock.Jr.1924.720p.BluRay.x264-GROUP',
              TorrentState.metaDownloading,
              'metaDL',
              progress: 0,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.checking,
              'checkingDL',
              progress: 0.87,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Selected · a lamp wash at 8% with a 40% lamp border, after a '
        'long-press starts selection · the bar is the blue tone, in progress',
        (_) => TorrentTile(
          torrent: _torrent(
            'Nosferatu.1922.1080p.BluRay.x264-GROUP',
            TorrentState.downloading,
            'downloading',
            progress: 0.63,
            dlSpeed: 25 * _mb,
            eta: 720,
          ),
          selected: true,
          onTap: _noop,
          onLongPress: _noop,
        ),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile on the desktop · the same plate in the wider queue column',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.1080p.BluRay.x264-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.63,
              size: 9 * _gb,
              dlSpeed: 25 * _mb,
              upSpeed: 1200 * 1024,
              eta: 720,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.stalled,
              'stalledDL',
              progress: 0.41,
              size: 22 * _gb,
            ),
            onTap: _noop,
          ),
        ]),
        width: 720,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
