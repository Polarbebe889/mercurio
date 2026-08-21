import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

/// Servicio de subida de "drops" de foto.
///
/// CAUSA DEL BUG (422 / application-octet-stream):
/// `http.MultipartFile.fromPath('file', path)` sin el parámetro
/// `contentType` manda por defecto `application/octet-stream`. FastAPI
/// recibe el UploadFile con ese content_type genérico y tu validación
/// (o Starlette) lo rechaza porque no reconoce el archivo como imagen.
///
/// FIX: detectamos el MIME real del archivo con el paquete `mime` y se lo
/// pasamos explícitamente a MultipartFile como `MediaType`.
class PhotoUploadService {
  final String baseUrl;
  final String Function() getAuthToken;
  final String Function()? getUsername;

  PhotoUploadService({required this.baseUrl, required this.getAuthToken, this.getUsername});

  Future<Map<String, dynamic>> uploadDrop({
    required File imageFile,
    String? caption,
  }) async {
    // 1. Detecta el MIME type real (revisa extensión y, si hace falta,
    //    las primeras bytes del archivo — más confiable que asumir).
    final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
    final mimeParts = mimeType.split('/');

    if (mimeParts.first != 'image') {
      throw Exception('El archivo seleccionado no es una imagen válida ($mimeType)');
    }

    final uri = Uri.parse('$baseUrl/drops');
    final request = http.MultipartRequest('POST', uri);
    request.headers['x-token'] = getAuthToken();
    final uname = getUsername?.call();
    if (uname != null && uname.isNotEmpty) {
      request.headers['x-user-id'] = uname;
      request.headers['x-username'] = uname;
    }

    // 2. ESTE ES EL FIX: contentType explícito en vez de dejar el default.
    final multipartFile = await http.MultipartFile.fromPath(
      'file', // debe coincidir EXACTO con el nombre del parámetro en FastAPI
      imageFile.path,
      contentType: MediaType(mimeParts[0], mimeParts[1]),
    );
    request.files.add(multipartFile);

    if (caption != null && caption.trim().isNotEmpty) {
      request.fields['caption'] = caption.trim();
    }

    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'body': response.body};
      }

      throw Exception('Error ${response.statusCode} al subir el drop: ${response.body}');
    } on SocketException {
      throw Exception('Sin conexión al servidor. Revisa tu internet.');
    } on TimeoutException {
      throw Exception('La subida tardó demasiado. Intenta de nuevo.');
    }
  }
}

/// -----------------------------------------------------------------------
/// pubspec.yaml — dependencias necesarias para este fix:
///   http: ^1.2.1
///   http_parser: ^4.0.2   <- necesario para MediaType
///   mime: ^1.0.5           <- necesario para lookupMimeType
/// -----------------------------------------------------------------------
