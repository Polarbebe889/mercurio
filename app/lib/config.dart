/// Configuración central de El Bunker.
///
/// - Para probar en emulador Android usa:  http://10.0.2.2:8847
/// - Para tu celular contra tu máquina usa la IP local:  http://192.168.x.x:8847
/// - Producción (Render):  https://el-bunker.onrender.com
class AppConfig {
  static const String apiBase = 'https://mercurio-9haf.onrender.com';
  static const String joinCode = 'BUNKER-6';

  static String get wsUrl =>
      apiBase.replaceFirst('http', 'ws') + '/ws';

  static String fullUrl(String path) =>
      path.startsWith('http') ? path : apiBase + path;
}