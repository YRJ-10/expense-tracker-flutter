/// Template konfigurasi backend untuk pengguna yang melakukan clone project.
/// Salin file ini menjadi `app_config.dart` dan isi dengan konfigurasi Cloudflare Worker Anda.
class AppConfig {
  /// URL Cloudflare Worker Anda (misal: https://expense-tracker-gmail.your-subdomain.workers.dev)
  static const String backendUrl = 'https://YOUR-WORKER-SUBDOMAIN.workers.dev';

  /// Token rahasia yang sama dengan secret WORKER_AUTH_TOKEN di Cloudflare Worker Anda
  static const String workerAuthToken = 'YOUR_WORKER_AUTH_TOKEN';
}
