class MiniAppBrowserConfig {
  final String appId;
  final List<String> allowedDomains;
  final String sdkVersion;

  const MiniAppBrowserConfig({
    required this.appId,
    required this.allowedDomains,
    this.sdkVersion = '1.0',
  });
}
