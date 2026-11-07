class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const developmentLoginEmail = String.fromEnvironment(
    'DEV_LOGIN_EMAIL',
  );
  static const developmentLoginPassword = String.fromEnvironment(
    'DEV_LOGIN_PASSWORD',
  );
  static const publicAppUrl = String.fromEnvironment('PUBLIC_APP_URL');
  static const buildId = String.fromEnvironment(
    'BUILD_ID',
    defaultValue: '20261107_1829',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
