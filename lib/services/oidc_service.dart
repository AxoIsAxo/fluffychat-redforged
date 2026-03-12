import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/platform_infos.dart';

/// Result of a successful OIDC login containing tokens and device info.
class OidcLoginResult {
  final String accessToken;
  final String? refreshToken;
  final String deviceId;
  final int? expiresIn;

  OidcLoginResult({
    required this.accessToken,
    this.refreshToken,
    required this.deviceId,
    this.expiresIn,
  });
}

class OidcService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Port for the local callback server on desktop
  static const int _callbackPort = 32847;
  static String get _redirectUri => 'http://localhost:$_callbackPort/callback';

  // Track active server to prevent double-bind
  static HttpServer? _activeServer;

  static String _generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return 'FLUFFYREDFORGED_${base64Url.encode(values).replaceAll('=', '')}';
  }

  /// Generate a cryptographically random string for state/code_verifier.
  static String _generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  /// Generate PKCE code challenge from code verifier.
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Step 1: Discover OIDC metadata from the homeserver (MSC2965).
  static Future<Map<String, dynamic>?> discoverMetadata(
    String homeserver,
  ) async {
    try {
      final baseUrl =
          homeserver.endsWith('/') ? homeserver : '$homeserver/';
      final url =
          '${baseUrl}_matrix/client/unstable/org.matrix.msc2965/auth_metadata';
      Logs().i('OIDC Discovery: fetching $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('issuer')) {
          Logs().i('OIDC Discovery: found issuer ${data['issuer']}');
          return data;
        }
      }
    } catch (e) {
      Logs().w('OIDC Discovery failed', e);
    }
    return null;
  }

  /// Step 2: Register the client dynamically (MSC2966).
  /// Caches the client_id per homeserver.
  static Future<String?> registerClient(
    Map<String, dynamic> metadata,
    String homeserver,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // v2: re-register with localhost redirect URI
    final cacheKey = 'oidc_client_id_v2_$homeserver';
    final cachedId = prefs.getString(cacheKey);
    if (cachedId != null) {
      Logs().i('OIDC: Using cached client_id for $homeserver');
      return cachedId;
    }

    final registrationEndpoint = metadata['registration_endpoint'];
    if (registrationEndpoint == null) {
      Logs().w('OIDC: No registration_endpoint in metadata');
      return null;
    }

    final body = {
      'application_type': 'native',
      'client_name': 'FluffyChat Redforged',
      'client_uri': 'https://github.com/AxoIsAxo/fluffychat-redforged',
      'token_endpoint_auth_method': 'none',
      'grant_types': ['authorization_code', 'refresh_token'],
      'redirect_uris': [_redirectUri],
      'response_types': ['code'],
      'contacts': [],
    };

    Logs().i('OIDC: Registering client at $registrationEndpoint');
    Logs().i('OIDC: Registration body: ${jsonEncode(body)}');

    final response = await http.post(
      Uri.parse(registrationEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final clientId = data['client_id'];
      if (clientId != null) {
        await prefs.setString(cacheKey, clientId);
        Logs().i('OIDC: Registered client_id: $clientId');
        return clientId;
      }
    }
    Logs().w(
      'OIDC Client Registration failed (${response.statusCode}): ${response.body}',
    );
    return null;
  }

  /// Steps 3-5: Full login flow for desktop platforms.
  /// Opens browser, starts local server, handles callback, exchanges code.
  static Future<OidcLoginResult?> login(
    Map<String, dynamic> metadata,
    String clientId, {
    String? homeserver,
  }) async {
    final deviceId = _generateDeviceId();
    final state = _generateRandomString(32);
    final codeVerifier = _generateRandomString(64);
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    final scope =
        'urn:matrix:org.matrix.msc2967.client:api:* urn:matrix:org.matrix.msc2967.client:device:$deviceId';

    final authEndpoint = metadata['authorization_endpoint'] as String;
    final tokenEndpoint = metadata['token_endpoint'] as String;

    // Build authorization URL
    final authUrl = Uri.parse(authEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': _redirectUri,
        'scope': scope,
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': codeChallenge,
      },
    );

    Logs().i('OIDC: Opening authorization URL in browser');
    Logs().i('OIDC: Auth URL: $authUrl');

    // Start local HTTP server to catch the callback
    HttpServer? server;
    try {
      // Close any existing server from a previous attempt
      if (_activeServer != null) {
        await _activeServer!.close(force: true);
        _activeServer = null;
      }

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _callbackPort);
      _activeServer = server;
      Logs().i('OIDC: Local callback server listening on port $_callbackPort');

      // Launch browser
      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        Logs().w('OIDC: Failed to launch browser');
        await server.close();
        return null;
      }

      // Wait for the callback
      String? authCode;
      String? returnedState;

      await for (final request in server) {
        final uri = request.uri;
        Logs().i('OIDC: Received callback: ${uri.path}?${uri.query}');

        if (uri.path == '/callback') {
          authCode = uri.queryParameters['code'];
          returnedState = uri.queryParameters['state'];

          // Send a nice response to the browser
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html>
<head><title>FluffyChat Redforged</title></head>
<body style="font-family: sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: white;">
  <h1>✅ Login successful!</h1>
  <p>You can close this tab and return to FluffyChat Redforged.</p>
  <script>window.close();</script>
</body>
</html>
''');
          await request.response.close();
          break;
        } else {
          request.response
            ..statusCode = 404
            ..write('Not found');
          await request.response.close();
        }
      }

      await server.close();
      _activeServer = null;

      if (authCode == null) {
        Logs().w('OIDC: No authorization code received');
        return null;
      }

      // Verify state
      if (returnedState != state) {
        Logs().w(
          'OIDC: State mismatch! Expected: $state, Got: $returnedState',
        );
        return null;
      }

      Logs().i('OIDC: Authorization code received, exchanging for tokens...');

      // Step 5: Exchange code for tokens
      final tokenResponse = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': _redirectUri,
          'client_id': clientId,
          'code_verifier': codeVerifier,
        },
      );

      if (tokenResponse.statusCode == 200) {
        final tokenData = jsonDecode(tokenResponse.body);
        final accessToken = tokenData['access_token'] as String?;
        final refreshToken = tokenData['refresh_token'] as String?;
        final expiresIn = tokenData['expires_in'] as int?;

        if (accessToken != null) {
          Logs().i('OIDC: Token exchange successful!');
          await storeTokens(accessToken, refreshToken, deviceId, 
          homeserver: homeserver);
          return OidcLoginResult(
            accessToken: accessToken,
            refreshToken: refreshToken,
            deviceId: deviceId,
            expiresIn: expiresIn,
          );
        }
      }

      Logs().w(
        'OIDC: Token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}',
      );
      return null;
    } catch (e, s) {
      Logs().w('OIDC Login failed', e, s);
      await server?.close();
      _activeServer = null;
      return null;
    }
  }

  /// Store tokens securely.
  static Future<void> storeTokens(
    String accessToken,
    String? refreshToken,
    String deviceId, {
    String? homeserver,
    String? userId,
  }) async {
    await _secureStorage.write(key: 'oidc_access_token', value: accessToken);
    if (refreshToken != null) {
      await _secureStorage.write(
        key: 'oidc_refresh_token',
        value: refreshToken,
      );
    }
    await _secureStorage.write(key: 'oidc_device_id', value: deviceId);
    if (homeserver != null) {
      await _secureStorage.write(key: 'oidc_homeserver', value: homeserver);
    }
    if (userId != null) {
      await _secureStorage.write(key: 'oidc_user_id', value: userId);
    }
  }

  /// Load stored tokens.
  static Future<Map<String, String?>> loadTokens() async {
    return {
      'access_token': await _secureStorage.read(key: 'oidc_access_token'),
      'refresh_token': await _secureStorage.read(key: 'oidc_refresh_token'),
      'device_id': await _secureStorage.read(key: 'oidc_device_id'),
      'homeserver': await _secureStorage.read(key: 'oidc_homeserver'),
      'user_id': await _secureStorage.read(key: 'oidc_user_id'),
    };
  }

  /// Refresh an expired access token.
  static Future<OidcLoginResult?> refreshAccessToken(
    Map<String, dynamic> metadata,
    String clientId,
    String refreshToken,
  ) async {
    final tokenEndpoint = metadata['token_endpoint'] as String;

    try {
      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'] as String?;
        final newRefreshToken = data['refresh_token'] as String?;
        final expiresIn = data['expires_in'] as int?;

        if (newAccessToken != null) {
          final deviceId =
              await _secureStorage.read(key: 'oidc_device_id') ?? '';
          await storeTokens(
            newAccessToken,
            newRefreshToken ?? refreshToken,
            deviceId,
          );
          return OidcLoginResult(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken ?? refreshToken,
            deviceId: deviceId,
            expiresIn: expiresIn,
          );
        }
      }

      Logs().w(
        'OIDC Refresh failed (${response.statusCode}): ${response.body}',
      );
    } catch (e) {
      Logs().w('OIDC Refresh failed', e);
    }
    return null;
  }

  /// Clear stored OIDC tokens (for logout).
  static Future<void> clearTokens() async {
    await _secureStorage.delete(key: 'oidc_access_token');
    await _secureStorage.delete(key: 'oidc_refresh_token');
    await _secureStorage.delete(key: 'oidc_device_id');
  }
}
