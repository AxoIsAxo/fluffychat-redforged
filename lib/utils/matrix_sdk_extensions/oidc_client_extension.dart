import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluffychat/services/oidc_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Custom Client class that handles OIDC token refresh properly
class OidcAwareClient extends Client {
  OidcAwareClient(
    super.clientName, {
    super.httpClient,
    super.verificationMethods,
    super.importantStateEvents,
    super.customImageResizer,
    super.logLevel,
    required super.database,
    super.supportedLoginTypes,
    super.nativeImplementations,
    super.defaultNetworkRequestTimeout,
    super.enableDehydratedDevices,
    super.shareKeysWith,
    super.onSoftLogout,
    super.sendTimelineEventTimeout,
  });

  @override
  Future<void> refreshAccessToken({Duration? customRefreshTokenLifetime}) async {
    Logs().i('OIDC: refreshAccessToken called - checking if OIDC session');
    
    // Check if this is an OIDC session
    final tokens = await OidcService.loadTokens();
    final accessToken = tokens['access_token'];
    final refreshToken = tokens['refresh_token'];
    final deviceId = tokens['device_id'];
    
    Logs().i('OIDC: Stored access token exists: ${accessToken != null}');
    Logs().i('OIDC: Stored refresh token exists: ${refreshToken != null}');
    Logs().i('OIDC: Current client access token: ${this.accessToken?.substring(0, 10) ?? 'null'}...');
    
    // If no OIDC tokens, fall back to standard refresh
    if (accessToken == null || refreshToken == null) {
      Logs().i('No OIDC tokens found, using standard refresh');
      await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
      return;
    }
    
    // Check if current access token matches OIDC token OR if client token is null (indicating logout)
    if (this.accessToken != null && this.accessToken != accessToken) {
      // Not an OIDC session, use standard refresh
      Logs().i('Current token does not match OIDC token, using standard refresh');
      await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
      return;
    }
    
    Logs().i('OIDC: Refreshing access token...');
    
    try {
      // Get homeserver from stored tokens or current client
      Uri homeserverUri;
      if (this.homeserver != null) {
        homeserverUri = this.homeserver!;
      } else {
        // Try to get homeserver from secure storage
        const secureStorage = FlutterSecureStorage();
        final storedHomeserver = await secureStorage.read(key: 'oidc_homeserver');
        if (storedHomeserver == null) {
          Logs().w('OIDC: No homeserver found, falling back to standard refresh');
          await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
          return;
        }
        homeserverUri = Uri.parse(storedHomeserver);
      }
      
      // Get OIDC metadata for this homeserver
      final metadata = await OidcService.discoverMetadata(homeserverUri.toString());
      if (metadata == null) {
        Logs().w('OIDC: No metadata found, falling back to standard refresh');
        await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
        return;
      }
      
      // Get cached client ID
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'oidc_client_id_v2_$homeserverUri';
      final clientId = prefs.getString(cacheKey);
      if (clientId == null) {
        Logs().w('OIDC: No client ID found, falling back to standard refresh');
        await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
        return;
      }
      
      // Refresh the token using OIDC service
      final result = await OidcService.refreshAccessToken(
        metadata,
        clientId,
        refreshToken,
      );
      
      if (result != null) {
        Logs().i('OIDC: Token refresh successful');
        // Store the new tokens
        await OidcService.storeTokens(
          result.accessToken,
          result.refreshToken,
          result.deviceId,
        );
        
        // Update the client's access token
        this.accessToken = result.accessToken;
        
        // The client might be in a logged out state internally
        // We need to reset the login state properly
        // First, check if the client thinks it's logged out
        if (!this.isLogged()) {
          Logs().i('OIDC: Client is in logged out state, attempting to restore...');
          try {
            // Try to get the user ID from the stored device ID or fetch it
            if (this.userID == null && result.deviceId != null) {
              // Try to fetch user ID using whoami
              try {
                final whoami = await this.request(
                  RequestType.GET,
                  '/_matrix/client/v3/account/whoami',
                );
                final userId = whoami['user_id'] as String?;
                if (userId != null) {
                  Logs().i('OIDC: Restored user ID: $userId');
                  // The userID should be automatically set by the SDK after the request
                }
              } catch (e) {
                Logs().w('OIDC: Could not fetch user ID after refresh', e);
              }
            }
            
            // Try to trigger a state change to restore the client
            // This simulates what happens during a successful login
            super.onLoginStateChanged.add(LoginState.loggedIn);
            
            // Trigger a sync to restore the client state
            await this.sync(filter: null);
          } catch (e) {
            Logs().w('Failed to restore client state after token refresh', e);
          }
        }
        
        Logs().i('OIDC: Token refresh and state restoration complete');
      } else {
        Logs().w('OIDC: Token refresh failed, falling back to standard refresh');
        await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
      }
    } catch (e, s) {
      Logs().w('OIDC: Token refresh error, falling back to standard refresh', e, s);
      await super.refreshAccessToken(customRefreshTokenLifetime: customRefreshTokenLifetime);
    }
  }
}
