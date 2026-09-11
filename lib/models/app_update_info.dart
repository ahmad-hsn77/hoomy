class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String minimumSupportedVersion;
  final String updateUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.updateUrl,
    required this.releaseNotes,
  });

  bool get hasUpdate => compareVersions(latestVersion, currentVersion) > 0;

  bool get requiresUpdate =>
      minimumSupportedVersion.isNotEmpty &&
      compareVersions(minimumSupportedVersion, currentVersion) > 0;

  factory AppUpdateInfo.fromJson(
    Map<String, dynamic> value, {
    required String currentVersion,
  }) {
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: (value['latestVersion'] ?? currentVersion).toString(),
      minimumSupportedVersion:
          (value['minimumSupportedVersion'] ?? '').toString(),
      updateUrl: (value['updateUrl'] ?? '').toString(),
      releaseNotes: (value['releaseNotes'] ?? '').toString(),
    );
  }
}

int compareVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

List<int> _versionParts(String value) {
  final withoutPreRelease = value.split('-').first;
  final buildSplit = withoutPreRelease.split('+');
  final nameParts = buildSplit.first
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final buildNumber = buildSplit.length > 1
      ? int.tryParse(buildSplit[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
      : 0;
  return [...nameParts, buildNumber];
}
