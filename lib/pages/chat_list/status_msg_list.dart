import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/mxc_image_viewer.dart';

class StatusMessageList extends StatelessWidget {
  final void Function() onStatusEdit;

  const StatusMessageList({required this.onStatusEdit, super.key});

  static const double height = 116;

  void _onStatusTab(BuildContext context, Profile profile) {
    final client = Matrix.of(context).client;
    if (profile.userId == client.userID) {
      onStatusEdit();
      return;
    }

    UserDialog.show(context: context, profile: profile);
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final interestingPresences = client.interestingPresences;

    return StreamBuilder(
      stream: client.onSync.stream.rateLimit(const Duration(seconds: 3)),
      builder: (context, snapshot) {
        return AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: Curves.easeInOut,
          child: FutureBuilder(
            initialData: interestingPresences
                // ignore: deprecated_member_use
                .map((userId) => client.presences[userId])
                .whereType<CachedPresence>(),
            future: Future.wait(
              client.interestingPresences.map(
                (userId) => client.fetchCurrentPresence(
                  userId,
                  fetchOnlyFromCached: true,
                ),
              ),
            ),
            builder: (context, snapshot) {
              final presences = snapshot.data
                  ?.where(isInterestingPresence)
                  .toList();

              // If no presences are interesting, we hide the presence header.
              if (presences == null || presences.isEmpty) {
                return const SizedBox.shrink();
              }

              // Make sure own entry is at the first position. Sort by last
              // active instead.
              presences.sort((a, b) {
                if (a.userid == client.userID) return -1;
                if (b.userid == client.userID) return 1;
                return b.sortOrderDateTime.compareTo(a.sortOrderDateTime);
              });

              return SizedBox(
                height: StatusMessageList.height,
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    top: 8.0,
                    bottom: 6.0,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: presences.length,
                  itemBuilder: (context, i) => PresenceAvatar(
                    presence: presences[i],
                    height: StatusMessageList.height,
                    onStatusEdit: onStatusEdit,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class PresenceAvatar extends StatelessWidget {
  final CachedPresence presence;
  final double height;
  final void Function() onStatusEdit;

  const PresenceAvatar({
    required this.presence,
    required this.height,
    required this.onStatusEdit,
    super.key,
  });

  Future<(Profile, String?)> _fetchData(BuildContext context) async {
    final client = Matrix.of(context).client;
    final profile = await client.getProfileFromUserId(presence.userid);
    String? statusImage;
    try {
      final response = await client.request(
        RequestType.GET,
        '/client/v3/profile/${presence.userid}/im.fluffychat.status_image',
      );
      statusImage = response['im.fluffychat.status_image'] as String?;
    } catch (_) {}
    return (profile, statusImage);
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = height - 16 - 16 - 6;
    final client = Matrix.of(context).client;

    return FutureBuilder<(Profile, String?)>(
      future: _fetchData(context),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final profile = snapshot.data?.$1;
        final statusImage = snapshot.data?.$2;

        final displayName =
            profile?.displayName ??
            presence.userid.localpart ??
            presence.userid;
        final statusMsg = presence.statusMsg;
        final hasStatus = (statusMsg?.isNotEmpty ?? false) || (statusImage?.isNotEmpty ?? false);

        const statusMsgBubbleElevation = 6.0;
        final statusMsgBubbleShadowColor = theme.colorScheme.surfaceBright;
        final statusMsgBubbleColor = Colors.white.withAlpha(212);

        final ringGradient = hasStatus
            ? const LinearGradient(
                colors: [Colors.greenAccent, Colors.green, Colors.tealAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : presence.gradient;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: SizedBox(
            width: avatarSize,
            child: Column(
              children: [
                HoverBuilder(
                  builder: (context, hovered) {
                    return AnimatedScale(
                      scale: hovered ? 1.15 : 1.0,
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(avatarSize),
                        onTap: profile == null
                            ? null
                            : () async {
                                if (presence.userid == client.userID) {
                                  onStatusEdit();
                                  return;
                                }

                                if (!hasStatus) {
                                  UserDialog.show(
                                    context: context,
                                    profile: profile,
                                  );
                                  return;
                                }

                                final choice = await showModalActionPopup<String>(
                                  context: context,
                                  title: displayName,
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
                                  ],
                                );

                                if (choice == 'picture') {
                                  if (profile.avatarUrl != null) {
                                    showDialog(
                                      context: context,
                                      builder: (_) => MxcImageViewer(profile.avatarUrl!),
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
                                }
                              },
                        child: Material(
                          borderRadius: BorderRadius.circular(avatarSize),
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  gradient: ringGradient,
                                  borderRadius: BorderRadius.circular(
                                    avatarSize,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  height: avatarSize - 6,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(
                                      avatarSize,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(3.0),
                                  child: Avatar(
                                    name: displayName,
                                    mxContent: profile?.avatarUrl,
                                    size: avatarSize - 12,
                                  ),
                                ),
                              ),
                              if (presence.userid == client.userID)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: FloatingActionButton.small(
                                      heroTag: null,
                                      onPressed: onStatusEdit,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.add_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              if (statusImage != null && statusImage.isNotEmpty)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Material(
                                    elevation: statusMsgBubbleElevation,
                                    shadowColor: statusMsgBubbleShadowColor,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius / 2,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    color: statusMsgBubbleColor,
                                    child: MxcImage(
                                      uri: Uri.tryParse(statusImage),
                                      width: avatarSize / 2.5,
                                      height: avatarSize / 2.5,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              else if (statusMsg != null && statusMsg.isNotEmpty)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  right: 0,
                                  child: Column(
                                    spacing: 2,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: .min,
                                    children: [
                                      Material(
                                        elevation: statusMsgBubbleElevation,
                                        shadowColor: statusMsgBubbleShadowColor,
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius / 2,
                                        ),
                                        color: statusMsgBubbleColor,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2.0,
                                            horizontal: 4.0,
                                          ),
                                          child: Text(
                                            statusMsg,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on Client {
  Set<String> get interestingPresences {
    final allHeroes = rooms
        .map((room) => room.summary.mHeroes)
        .fold(
          <String>{},
          (previousValue, element) => previousValue..addAll(element ?? {}),
        );
    allHeroes.add(userID!);
    return allHeroes;
  }
}

bool isInterestingPresence(CachedPresence presence) =>
    !presence.presence.isOffline || (presence.statusMsg?.isNotEmpty ?? false);

extension on CachedPresence {
  DateTime get sortOrderDateTime =>
      lastActiveTimestamp ??
      (currentlyActive == true
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(0));

  LinearGradient get gradient => presence.isOnline == true
      ? LinearGradient(
          colors: [Colors.green, Colors.green.shade200, Colors.green.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : presence.isUnavailable
      ? LinearGradient(
          colors: [
            Colors.yellow,
            Colors.yellow.shade200,
            Colors.yellow.shade900,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Colors.grey, Colors.grey.shade200, Colors.grey.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
}
