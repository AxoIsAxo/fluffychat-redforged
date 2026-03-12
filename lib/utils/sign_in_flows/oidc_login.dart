import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/services/oidc_service.dart';
import 'package:fluffychat/utils/platform_infos.dart';

Future<void> oidcLoginFlow(
  Client client,
  BuildContext context,
  bool signUp,
  Map<String, dynamic> metadata, {
  Uri? homeserver,
}) async {
  Logs().i('Starting Matrix Native OIDC Flow...');

  final homeserverUrl = (homeserver ?? client.homeserver)!.toString();
  final clientId = await OidcService.registerClient(metadata, homeserverUrl);
  if (clientId == null) {
    throw Exception('Failed to register OIDC client');
  }

  Logs().i('OIDC: Client registered, starting login flow...');

  final loginResult = await OidcService.login(metadata, clientId, homeserver: homeserverUrl);
  if (loginResult == null) {
    throw Exception('OIDC Login failed or was cancelled');
  }

  Logs().i('OIDC: Login successful, initializing Matrix client...');

  final hsUri = homeserver ?? client.homeserver;

  // Initialize with token — the SDK will fetch the user ID during init/sync
  await client.init(
    newToken: loginResult.accessToken,
    newUserID: null,
    newHomeserver: hsUri,
    newDeviceID: loginResult.deviceId,
    newDeviceName: PlatformInfos.clientName,
  );

  // Try to get user ID from whoami, but don't fail if it doesn't work
  // (some OIDC-only servers don't support the standard whoami endpoint)
  String? userId;
  try {
    final whoami = await client.request(
      RequestType.GET,
      '/_matrix/client/v3/account/whoami',
    );
    userId = whoami['user_id'] as String?;
    Logs().i('OIDC: Logged in as $userId');
  } catch (e) {
    Logs().w('OIDC: whoami failed, trying userID from client', e);
    userId = client.userID;
  }

  if (userId != null && userId != client.userID) {
    // Re-initialize with the correct user ID
    await client.init(
      newToken: loginResult.accessToken,
      newUserID: userId,
      newHomeserver: hsUri,
      newDeviceID: loginResult.deviceId,
      newDeviceName: PlatformInfos.clientName,
    );
  }

  Logs().i('OIDC: Matrix client initialized successfully as ${client.userID}');
  
  // Store the user ID for future refresh operations
  if (client.userID != null) {
    await OidcService.storeTokens(
      loginResult.accessToken,
      loginResult.refreshToken,
      loginResult.deviceId,
      homeserver: homeserverUrl,
      userId: client.userID,
    );
  }
}
