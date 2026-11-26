import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/media_browser_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

export 'package:cupola/features/jellyfin/presentation/media_browser_providers.dart';

/// Jellyfin's set. Every `jellyfin*Provider` below is a field of it, under the
/// name callers and tests override it by.
final jellyfinProviders = MediaBrowserProviders<JellyfinClient>(
  ServiceKey.jellyfin,
  create: (transport, viewerId) => JellyfinClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    userId: viewerId,
    pinnedCertFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.jellyfin),
  ),
);

/// The providers of a MediaBrowser [service], for a widget written once for
/// every server of the family (the Users, Devices, Tasks and Activity tabs,
/// the viewer picker). Throws for a service that is not one: a widget that
/// asks has been handed the wrong key, and an answer about some other server
/// would be worse than the throw.
MediaBrowserProviders<MediaBrowserClient> mediaBrowserProvidersOf(
  ServiceKey service,
) => switch (service) {
  ServiceKey.jellyfin => jellyfinProviders,
  _ => throw ArgumentError.value(
    service,
    'service',
    'is not a MediaBrowser server',
  ),
};

final jellyfinClientForProvider = jellyfinProviders.client.forConnection;

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// Widgets should depend on this one: nothing above the data layer has any
/// business knowing whether it is talking to Jellyfin or Plex, and a screen that
/// takes the interface can be reused for both, which is the entire point of
/// having it. `cancelToken` now lives on `StreamServerClient` itself, so even the
/// cancellable per-item fetches below go through here; the concrete provider
/// stays public only for the Jellyfin-specific extras (`getViewers` filtering,
/// the raw item mapper) that genuinely have no cross-server meaning.
final jellyfinServerProvider = jellyfinProviders.server;

/// Everything playing right now, most expensive first.
///
/// Not polled from here: the dashboard owns its own refresh cadence the way
/// `torrentDetailPollingProvider` does, and a timer buried in a data provider
/// would keep firing behind a screen nobody is looking at.
final jellyfinSessionsProvider = jellyfinProviders.sessions;

/// The libraries this server exposes.
///
/// `retry: noProviderRetry` from here down, for the reason
/// [jellyfinSessionsProvider] gives one step above: the default retry re-runs a
/// failed build ten times behind an exponential backoff and holds the future
/// until it has, so a server that has gone dark is a spinner for the better
/// part of a minute before any surface can say "unreachable" and offer the
/// Retry it already draws. (The "not configured" throw never needed the flag;
/// it reaches a watcher as a `ProviderException`, which `defaultRetry`
/// declines on its own.)
final jellyfinLibrariesProvider = jellyfinProviders.libraries;

/// One item at any depth, by id.
///
/// Resolves from the id alone so `ServiceRoutes.jellyfinItem` works as a deep
/// link; `state.extra` stays preload/Hero data only.
///
/// `autoDispose` for two reasons: every item ever opened would otherwise be
/// retained forever, and the cancellation would never fire.
final jellyfinItemProvider = jellyfinProviders.item;

/// The children of a series, season or album: seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider = jellyfinProviders.itemChildren;

/// The libraries with the transport failure preserved, for the surfaces that
/// state a **figure** rather than draw a board (the KPI rail).
///
/// Written when `getLibraries()` still answered an unreachable server with
/// `const []`, wrong for a counter, where `0 libraries` is a claim nobody
/// made. A provider rather than a call the KPI layer makes on the client: it
/// caches, invalidates with everything else, and can be overridden by name.
/// The sessions had a twin of this too; it went once both reads threw, because
/// two caches of one sessions read let the figure and Now playing disagree.
final jellyfinStrictLibrariesProvider = jellyfinProviders.strictLibraries;
