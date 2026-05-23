import 'api_client.dart';

// Shared API instance for the whole app.
// Adjust baseUrl if running on Android emulator: use http://10.0.2.2:4000
final api = ApiClient(baseUrl: 'https://borrowease-crowdsourced-borrowing-app.onrender.com');
