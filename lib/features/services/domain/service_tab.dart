import 'package:cupola/features/settings/domain/service_key.dart';

/// Every view a service can show, and the word the app uses for it.
///
/// One closed vocabulary rather than a string per surface, because four things
/// have to agree about a tab and they are written in four different files: the
/// bar draws its label, the router mounts its branch, the breadcrumb prints it
/// as the third crumb, and a deep link spells it as a path segment. When those
/// were independent the breadcrumb title-cased whatever segment it found and
/// printed `Vms` and `Rss`, neither of which is how anyone writes them, and
/// neither of which any other surface said.
///
/// [segment] is the URL spelling and [label] the human one; they differ only
/// where English does.
enum ServiceTab {
  overview('overview', 'Overview'),

  // ── Seerr ────────────────────────────────────────────────────────────────
  requests('requests', 'Requests'),
  issues('issues', 'Issues'),
  users('users', 'Users'),

  // ── The \*arr family ──────────────────────────────────────────────────────
  library('library', 'Library'),
  calendar('calendar', 'Calendar'),
  queue('queue', 'Queue'),
  wanted('wanted', 'Wanted'),
  history('history', 'History'),

  // ── Bazarr ───────────────────────────────────────────────────────────────
  series('series', 'Series'),
  movies('movies', 'Movies'),
  providers('providers', 'Providers'),

  // ── Download clients ─────────────────────────────────────────────────────
  rss('rss', 'RSS'),

  // ── Prowlarr ─────────────────────────────────────────────────────────────
  indexers('indexers', 'Indexers'),
  stats('stats', 'Stats'),

  // ── Stream ───────────────────────────────────────────────────────────────
  libraries('libraries', 'Libraries'),
  devices('devices', 'Devices'),
  tasks('tasks', 'Tasks'),
  activity('activity', 'Activity'),
  activities('activities', 'Activities'),
  playlists('playlists', 'Playlists'),

  // ── Infrastructure ───────────────────────────────────────────────────────
  stacks('stacks', 'Stacks'),
  terminal('terminal', 'Terminal'),
  array('array', 'Array'),
  docker('docker', 'Docker'),
  vms('vms', 'VMs'),
  notifications('notifications', 'Notifications'),
  shares('shares', 'Shares');

  const ServiceTab(this.segment, this.label);

  /// The path segment, e.g. `on-deck` in `/dashboard/plex/on-deck`.
  final String segment;

  /// The word the bar and the breadcrumb print.
  final String label;

  static final Map<String, ServiceTab> _bySegment = {
    for (final tab in values) tab.segment: tab,
  };

  /// Resolves a path segment back to its tab, for the breadcrumb and for a
  /// deep link that names a tab the service does not have.
  static ServiceTab? fromSegment(String segment) => _bySegment[segment];
}

/// The bar, per service, in the order it is drawn.
///
/// Read off the nineteen service home boards. Three rules hold over the whole
/// table and are asserted by its tests rather than left to review:
///
///  * every list starts with [ServiceTab.overview]: opening a service always
///    lands there, and it is the only tab carrying the identity block and the
///    readouts;
///  * at most six entries, because past six the bar stops being a bar;
///  * no duplicates within a service.
///
/// TrueNAS is absent on purpose, and that absence is the contract: ten sections
/// are too many for a bar, so it keeps the console it already has. Everything
/// else in the stack follows the tab model.
const Map<ServiceKey, List<ServiceTab>> serviceTabs = {
  ServiceKey.seerr: [
    ServiceTab.overview,
    ServiceTab.requests,
    ServiceTab.issues,
    ServiceTab.users,
  ],
  // This fork: Radarr and Sonarr open on their Library, with no Overview and
  // no Queue (downloads live on Activity).
  ServiceKey.radarr: _arrLibraryTabs,
  ServiceKey.sonarr: _arrLibraryTabs,
  ServiceKey.qbittorrent: [
    ServiceTab.overview,
    ServiceTab.queue,
    ServiceTab.rss,
  ],
  ServiceKey.jellyfin: [
    ServiceTab.overview,
    ServiceTab.libraries,
    ServiceTab.users,
    ServiceTab.devices,
    ServiceTab.tasks,
    ServiceTab.activity,
  ],
  // The agent picker is the app-bar connection lens, not a tab (decision 41).
  ServiceKey.dockge: [
    ServiceTab.overview,
    ServiceTab.stacks,
    ServiceTab.terminal,
  ],
};

const List<ServiceTab> _arrLibraryTabs = [
  ServiceTab.library,
  ServiceTab.calendar,
  ServiceTab.wanted,
  ServiceTab.history,
];

/// The bar for [service], or null where the service does not have one.
///
/// Null is TrueNAS and nothing else, and callers must handle it rather than
/// defaulting to an empty bar: an empty bar is a service whose tabs failed to
/// load, which is a different thing from a console.
List<ServiceTab>? tabsFor(ServiceKey service) => serviceTabs[service];

/// The tab [path] is on, when it is on one of [service]'s.
///
/// Derived from the path, like the breadcrumb and for the same reason: a deep
/// link, a restored window and a cold start all arrive carrying nothing but a
/// location, so anything that reads the selection from state instead would be
/// wrong for the first frame of all three.
///
/// Returns null for a tab the service does not have, rather than the tab: a
/// link naming another service's view is not a place on this one.
ServiceTab? serviceTabOf(ServiceKey service, String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.length < 3 || segments[1] != service.routeParam) return null;
  final tab = ServiceTab.fromSegment(segments[2]);
  if (tab == null || !(tabsFor(service)?.contains(tab) ?? false)) return null;
  return tab;
}

/// Whether [path] is a tab's own root rather than a page pushed from it.
///
/// The one question the service shell's app-bar band has to ask. The band is
/// drawn above every branch navigator, so unlike the tab bar (which a pushed
/// page simply covers), it cannot be hidden by the page that wants it gone, and
/// has to hide itself. Two back chevrons in one corner is what this answers.
bool isServiceTabRoot(ServiceKey service, String path) =>
    serviceTabOf(service, path) != null &&
    Uri.parse(path).pathSegments.length == 3;
