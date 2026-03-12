import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluffychat/services/oidc_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluffychat/utils/platform_infos.dart';

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
        
        Logs().i('OIDC: After setting access token, isLogged(): ${this.isLogged()}, userID: ${this.userID}');
        
        // Simple state restoration - just update the essential fields
        // Don't try to re-initialize the client as it causes encryption issues during logout
        try {
          // Get stored user ID
          const secureStorage = FlutterSecureStorage();
          final storedUserId = await secureStorage.read(key: 'oidc_user_id');
          
          if (storedUserId != null) {
            Logs().i('OIDC: Restoring user ID from storage: $storedUserId');
            // userID is read-only, we can't directly set it
            // The client will get the user ID on the next sync or API call
          }
          
          // Trigger login state change to notify the app
          super.onLoginStateChanged.add(LoginState.loggedIn);
          
          Logs().i('OIDC: Basic state restoration complete');
        } catch (e) {
          Logs().w('OIDC: Error during basic state restoration', e);
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
