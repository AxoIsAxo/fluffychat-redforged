import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;
  final bioController = TextEditingController();
  bool isBioLoading = false;
  late MatrixState matrix;

  void updateProfile() => setState(() {
    profileUpdated = true;
    profileFuture = null;
  });

  Future<void> setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          profile?.displayName ?? matrix.client.userID!.localpart,
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  Future<void> logoutAction() async {
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSureYouWantToLogout,
          message: L10n.of(context).noBackupWarning,
          isDestructive: cryptoIdentityConnected == false,
          okLabel: L10n.of(context).logout,
          cancelLabel: L10n.of(context).cancel,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
    context.go('/');
  }

  Future<void> setAvatarAction() async {
    final profile = await profileFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  @override
  void initState() {
    super.initState();
    // Store matrix reference to avoid context access issues
    matrix = Matrix.of(context);
    // Delay checkBootstrap to avoid widget lifecycle issues
    Future.microtask(() {
      if (mounted) {
        checkBootstrap();
      }
    });
  }

  Future<void> checkBootstrap() async {
    if (!mounted) return;
    final client = matrix.client;
    if (!client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    if (!mounted) return;
    final state = await client.getCryptoIdentityState();
    if (mounted) {
      setState(() {
        cryptoIdentityConnected = state.initialized && state.connected;
      });
    }
  }

  bool? cryptoIdentityConnected;

  Future<void> firstRunBootstrapAction([_]) async {
    if (cryptoIdentityConnected == true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  Future<void> loadBio() async {
    if (isBioLoading) return;
    setState(() => isBioLoading = true);
    try {
      final response = await matrix.client.request(
        RequestType.GET,
        '/client/v3/profile/${matrix.client.userID}/im.fluffychat.bio',
      );
      if (mounted) {
        bioController.text = response['im.fluffychat.bio'] as String? ?? '';
      }
    } catch (_) {
      // Bio not set yet - that's fine, leave blank
    } finally {
      if (mounted) {
        setState(() => isBioLoading = false);
      }
    }
  }

  Future<void> setBioAction() async {
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editBio,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: bioController.text,
    );
    if (input == null) return;
    
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.request(
        RequestType.PUT,
        '/client/v3/profile/${matrix.client.userID}/im.fluffychat.bio',
        data: {'im.fluffychat.bio': input.trim()},
      ),
    );
    if (success.error == null) {
      bioController.text = input.trim();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).bioHasBeenChanged)),
        );
      }
    }
  }

  @override
  void dispose() {
    bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    profileFuture ??= matrix.client.getProfileFromUserId(matrix.client.userID!);
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
