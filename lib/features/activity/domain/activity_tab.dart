/// Activity's four views, each at its own address.
library;

import 'package:cupola/core/utils/service_routes.dart';

/// What Activity shows: one choice, never a filter over another.
///
/// The address says the view, as the bar's tabs do, so a link, a
/// notification and the back gesture land on the same one, and returning
/// to the tab finds it where it was left.
enum ActivityTab {
  /// This fork: History first, at Activity's own address; then Downloads.
  /// No All, no Requests.
  history('History', ServiceRoutes.activity),

  downloads('Downloads', ServiceRoutes.activityDownloads);

  const ActivityTab(this.label, this.location);

  /// The word on the tab.
  final String label;

  /// Where the view lives.
  final String location;
}
