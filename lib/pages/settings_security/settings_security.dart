import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/services/secure_credential_store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'settings_security_view.dart';

class SettingsSecurity extends StatefulWidget {
  const SettingsSecurity({super.key});

  @override
  SettingsSecurityController createState() => SettingsSecurityController();
}

class SettingsSecurityController extends State<SettingsSecurity> {
  bool? hasStoredRecoveryKey;
  bool? autoUnlockEnabled;

  @override
  void initState() {
    super.initState();
    _loadSecureStorageState();
  }

  Future<void> _loadSecureStorageState() async {
    final userId = Matrix.of(context).client.userID;
    if (userId == null) return;
    final hasKey = await SecureCredentialStore.hasRecoveryKey(userId);
    final autoUnlock =
        await SecureCredentialStore.isAutoUnlockSsssEnabled(userId);
    if (mounted) {
      setState(() {
        hasStoredRecoveryKey = hasKey;
        autoUnlockEnabled = autoUnlock;
      });
    }
  }

  Future<void> storeRecoveryKeyAction() async {
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).storeRecoveryKey,
      message: L10n.of(context).enterRecoveryKeyToStore,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      maxLines: 1,
      minLines: 1,
    );
    if (input == null || input.trim().isEmpty) return;

    final userId = Matrix.of(context).client.userID;
    if (userId == null) return;

    // Validate the recovery key by trying to unlock SSSS
    final client = Matrix.of(context).client;
    if (client.encryption != null) {
      try {
        final openSsss = client.encryption!.ssss.open();
        await openSsss.unlock(keyOrPassphrase: input.trim());
        await openSsss.maybeCacheAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context).invalidRecoveryKey)),
          );
        }
        return;
      }
    }

    await SecureCredentialStore.storeRecoveryKey(userId, input.trim());
    await SecureCredentialStore.setAutoUnlockSsss(userId, true);
    if (mounted) {
      setState(() {
        hasStoredRecoveryKey = true;
        autoUnlockEnabled = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).recoveryKeyStoredSuccess)),
      );
    }
  }

  Future<void> deleteStoredRecoveryKeyAction() async {
    final consent = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).deleteStoredRecoveryKey,
      message: L10n.of(context).deleteStoredRecoveryKeyDescription,
      okLabel: L10n.of(context).delete,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;

    final userId = Matrix.of(context).client.userID;
    if (userId == null) return;

    await SecureCredentialStore.clearAll(userId);
    if (mounted) {
      setState(() {
        hasStoredRecoveryKey = false;
        autoUnlockEnabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).recoveryKeyDeleted)),
      );
    }
  }

  Future<void> toggleAutoUnlockSsss(bool? value) async {
    if (value == null) return;
    final userId = Matrix.of(context).client.userID;
    if (userId == null) return;

    // If enabling auto-unlock but no recovery key stored, prompt to store one
    if (value && hasStoredRecoveryKey != true) {
      await storeRecoveryKeyAction();
      return;
    }

    await SecureCredentialStore.setAutoUnlockSsss(userId, value);
    if (mounted) {
      setState(() {
        autoUnlockEnabled = value;
      });
    }
  }

  Future<void> setAppLockAction() async {
    if (AppLock.of(context).isActive) {
      AppLock.of(context).showLockScreen();
    }
    final newLock = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).pleaseChooseAPasscode,
      message: L10n.of(context).pleaseEnter4Digits,
      cancelLabel: L10n.of(context).cancel,
      validator: (text) {
        if (text.isEmpty || (text.length == 4 && int.tryParse(text)! >= 0)) {
          return null;
        }
        return L10n.of(context).pleaseEnter4Digits;
      },
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLines: 1,
      minLines: 1,
      maxLength: 4,
    );
    if (newLock != null) {
      await AppLock.of(context).changePincode(newLock);
    }
  }

  Future<void> deleteAccountAction() async {
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).warning,
          message: L10n.of(context).deactivateAccountWarning,
          okLabel: L10n.of(context).ok,
          cancelLabel: L10n.of(context).cancel,
          isDestructive: true,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    final supposedMxid = Matrix.of(context).client.userID!;
    final mxid = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).confirmMatrixId,
      validator: (text) => text == supposedMxid
          ? null
          : L10n.of(context).supposedMxid(supposedMxid),
      isDestructive: true,
      okLabel: L10n.of(context).delete,
      cancelLabel: L10n.of(context).cancel,
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    final resp = await showFutureLoadingDialog(
      context: context,
      delay: false,
      future: () =>
          Matrix.of(context).client.uiaRequestBackground<IdServerUnbindResult?>(
            (auth) => Matrix.of(
              context,
            ).client.deactivateAccount(auth: auth, erase: true),
          ),
    );

    if (!resp.isError) {
      await showFutureLoadingDialog(
        context: context,
        future: () => Matrix.of(context).client.logout(),
      );
    }
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  Future<void> changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}
