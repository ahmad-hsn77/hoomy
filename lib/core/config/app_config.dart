class AppConfig {
  const AppConfig._();

  static const backendBaseUrl = String.fromEnvironment(
    'HOOMY_API_URL',
    defaultValue: 'https://hoomy-production-b7f6.up.railway.app',
  );

  static const appVersion = String.fromEnvironment(
    'HOOMY_APP_VERSION',
    defaultValue: '0.1.3+2005',
  );
}
