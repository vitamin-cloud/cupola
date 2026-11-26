/// Result from the delete confirmation dialog.
class DeleteMediaResult {
  final bool confirmed;
  final bool deleteFiles;
  final bool addExclusion;

  const DeleteMediaResult({
    required this.confirmed,
    this.deleteFiles = false,
    this.addExclusion = false,
  });

  static const cancelled = DeleteMediaResult(confirmed: false);
}

enum DeleteMediaType {
  movie(label: 'movie', serviceName: 'Radarr'),
  series(label: 'series', serviceName: 'Sonarr'),
  artist(label: 'artist', serviceName: 'Lidarr');

  const DeleteMediaType({required this.label, required this.serviceName});

  final String label;
  final String serviceName;
}
