import 'dart:convert';
import 'dart:io';

/// Dart entrypoint for the `bunny-upload` Appwrite function.
///
/// Expects a JSON body:
/// {
///   "path": "profiles/USER_ID/avatar_123.png",
///   "fileBase64": "BASE64_BYTES"
/// }
///
/// Uses environment variables set in the Appwrite function:
/// - BUNNY_STORAGE_ZONE
/// - BUNNY_STORAGE_KEY
/// - BUNNY_STORAGE_HOST
/// - BUNNY_CDN_BASE_URL
Future<dynamic> main(dynamic context) async {
  final req = context.req;
  final res = context.res;
  final env = context.env;

  if (req.method.toUpperCase() != 'POST') {
    return res.json({'error': 'Only POST allowed'}, 405);
  }

  try {
    final body = req.body ?? '{}';
    final data = jsonDecode(body) as Map<String, dynamic>;

    final objectPath = data['path'] as String?;
    final fileBase64 = data['fileBase64'] as String?;

    if (objectPath == null || fileBase64 == null) {
      return res.json(
        {'error': 'path and fileBase64 are required'},
        400,
      );
    }

    final zone = env['BUNNY_STORAGE_ZONE'];
    final key = env['BUNNY_STORAGE_KEY'];
    final host = env['BUNNY_STORAGE_HOST'] ?? 'storage.bunnycdn.com';
    final cdnBase = env['BUNNY_CDN_BASE_URL'];

    if (zone == null || key == null || cdnBase == null) {
      return res.json(
        {'error': 'Bunny configuration missing'},
        500,
      );
    }

    final bytes = base64Decode(fileBase64);
    final uri = Uri.https(host, '$zone/$objectPath');

    final httpClient = HttpClient();
    final httpReq = await httpClient.putUrl(uri);
    httpReq.headers.set('AccessKey', key);
    httpReq.headers.set('Content-Type', 'application/octet-stream');
    httpReq.add(bytes);
    final httpRes = await httpReq.close();

    if (httpRes.statusCode < 200 || httpRes.statusCode >= 300) {
      final errorBody = await utf8.decoder.bind(httpRes).join();
      return res.json(
        {
          'error': 'Bunny upload failed',
          'status': httpRes.statusCode,
          'body': errorBody,
        },
        502,
      );
    }

    final cleanBase =
        cdnBase.endsWith('/') ? cdnBase.substring(0, cdnBase.length - 1) : cdnBase;
    final cleanPath =
        objectPath.startsWith('/') ? objectPath.substring(1) : objectPath;
    final cdnUrl = '$cleanBase/$cleanPath';

    return res.json(
      {'path': objectPath, 'url': cdnUrl},
      200,
    );
  } catch (e) {
    return res.json(
      {'error': 'Upload failed', 'detail': e.toString()},
      500,
    );
  }
}

