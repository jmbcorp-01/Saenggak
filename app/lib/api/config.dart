/// Server settings, passed at build time:
///   flutter run --dart-define=API_URL=https://... \
///     --dart-define=COGNITO_REGION=us-east-1 --dart-define=COGNITO_CLIENT_ID=...
/// The values come from the CDK stack outputs. Without API_URL the app runs on
/// the offline demo backend.
class ApiConfig {
  const ApiConfig({required this.apiUrl, required this.region, required this.clientId});

  static const fromEnvironment = ApiConfig(
    apiUrl: String.fromEnvironment('API_URL'),
    region: String.fromEnvironment('COGNITO_REGION', defaultValue: 'us-east-1'),
    clientId: String.fromEnvironment('COGNITO_CLIENT_ID'),
  );

  final String apiUrl;
  final String region;
  final String clientId;

  bool get isDemo => apiUrl.isEmpty || clientId.isEmpty;
}
