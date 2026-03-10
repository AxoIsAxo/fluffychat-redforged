import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class Avatar extends StatelessWidget {
  final Uri? mxContent;
  final String? name;
  final double size;
  final void Function()? onTap;
  static const double defaultSize = 48;
  final Client? client;
  final String? presenceUserId;
  final Color? presenceBackgroundColor;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final ShapeBorder? shapeBorder;
  final Color? backgroundColor;
  final Color? textColor;

  const Avatar({
    this.mxContent,
    this.name,
    this.size = defaultSize,
    this.onTap,
    this.client,
    this.presenceUserId,
    this.presenceBackgroundColor,
    this.borderRadius,
    this.shapeBorder,
    this.icon,
    this.backgroundColor,
    this.textColor,
    super.key,
  });

  Future<String?> _fetchStatusImage(BuildContext context) async {
    final presenceUserId = this.presenceUserId;
    if (presenceUserId == null) return null;
    try {
      final client = this.client ?? Matrix.of(context).client;
      final response = await client.request(
        RequestType.GET,
        '/client/v3/profile/$presenceUserId/im.fluffychat.status_image',
      );
      return response['im.fluffychat.status_image'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = this.name;
    final fallbackLetters = name == null || name.isEmpty ? '@' : name.substring(0, 1);

    final noPic =
        mxContent == null ||
        mxContent.toString().isEmpty ||
        mxContent.toString() == 'null';
    final borderRadius = this.borderRadius ?? BorderRadius.circular(size / 2);
    final presenceUserId = this.presenceUserId;

    return PresenceBuilder(
      client: client,
      userId: presenceUserId,
      builder: (context, presence) {
        return FutureBuilder<String?>(
          future: _fetchStatusImage(context),
          builder: (context, snapshot) {
            final statusImage = snapshot.data;
            final hasStatus = (presence?.statusMsg?.isNotEmpty ?? false) ||
                (statusImage?.isNotEmpty ?? false);

            final container = Stack(
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: Material(
                    color: theme.brightness == Brightness.light ? Colors.white : Colors.black,
                    shape: shapeBorder ??
                        RoundedSuperellipseBorder(
                          borderRadius: borderRadius,
                          side: hasStatus
                              ? const BorderSide(color: Colors.greenAccent, width: 3)
                              : BorderSide.none,
                        ),
                    clipBehavior: Clip.antiAlias,
                    child: MxcImage(
                      client: client,
                      borderRadius: borderRadius,
                      key: ValueKey(mxContent.toString()),
                      cacheKey: '${mxContent}_$size',
                      uri: mxContent,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      placeholder: (_) => noPic
                          ? Container(
                              decoration: BoxDecoration(
                                color: backgroundColor ?? name?.lightColorAvatar,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                fallbackLetters,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'RobotoMono',
                                  color: textColor ?? Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: (size / 2.5).roundToDouble(),
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.person_2,
                                color: theme.colorScheme.tertiary,
                                size: size / 1.5,
                              ),
                            ),
                    ),
                  ),
                ),
                if (presenceUserId != null &&
                    presence != null &&
                    !(presence.presence == PresenceType.offline &&
                        presence.lastActiveTimestamp == null)) ...[
                  Positioned(
                    bottom: -3,
                    right: -3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: presenceBackgroundColor ?? theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: presence.presence.isOnline
                              ? Colors.green
                              : presence.presence.isUnavailable
                                  ? Colors.orange
                                  : Colors.grey,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            width: 1,
                            color: theme.colorScheme.surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );

            void handleTap() async {
              if (onTap != null && !hasStatus) {
                onTap!();
                return;
              }

              if (presenceUserId == null) {
                onTap?.call();
                return;
              }

              final client = this.client ?? Matrix.of(context).client;
              final profile = await client.getProfileFromUserId(presenceUserId);

              if (!hasStatus) {
                onTap?.call();
                return;
              }

              final choice = await showModalActionPopup<String>(
                context: context,
                title: name ?? profile.displayName ?? presenceUserId,
                cancelLabel: L10n.of(context).cancel,
                actions: [
                  AdaptiveModalAction(
                    value: 'picture',
                    label: L10n.of(context).viewProfilePicture,
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                  AdaptiveModalAction(
                    value: 'status',
                    label: L10n.of(context).viewStatus,
                    icon: const Icon(Icons.info_outlined),
                  ),
                  if (onTap != null)
                    AdaptiveModalAction(
                      value: 'action',
                      label: L10n.of(context).openChat,
                      icon: const Icon(Icons.chat_outlined),
                    ),
                ],
              );

              if (choice == 'picture') {
                if (mxContent != null) {
                  showDialog(
                    context: context,
                    builder: (_) => MxcImageViewer(mxContent!),
                  );
                }
              } else if (choice == 'status') {
                if (statusImage != null && statusImage.isNotEmpty) {
                  showDialog(
                    context: context,
                    builder: (_) => MxcImageViewer(Uri.parse(statusImage)),
                  );
                } else {
                  UserDialog.show(
                    context: context,
                    profile: profile,
                  );
                }
              } else if (choice == 'action') {
                onTap?.call();
              }
            }

            return MouseRegion(
              cursor: (onTap != null || hasStatus) ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: (onTap != null || hasStatus) ? handleTap : null,
                child: container,
              ),
            );
          },
        );
      },
    );
  }
}
