import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/call/call_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../blocs/professionals/professionals_bloc.dart';
import '../../cards/portfolio_sections.dart';
import '../../config/app_config.dart';
import '../../models/call_models.dart';
import '../../models/chat_message.dart';
import '../../models/professional.dart';
import '../../services/socket_service.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/chat_composer.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/presence_dot.dart';

/// A coach's portfolio with the conversation directly beneath it.
///
/// One scroll on purpose. Splitting portfolio and chat into tabs would
/// hide the credentials the moment someone starts typing — but the
/// credentials are what make them comfortable typing at all.
class ProfessionalDetailScreen extends StatelessWidget {
  const ProfessionalDetailScreen({
    required this.professionalId,
    this.preview,
    super.key,
  });

  final String professionalId;

  /// The list-screen copy, so the header paints immediately instead of
  /// flashing a spinner over data we already have.
  final Professional? preview;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // No explicit type argument: BlocProvider is bounded by
      // StateStreamableSource, which `dynamic` does not satisfy.
      providers: [
        BlocProvider<ProfessionalsBloc>(
          create: (_) =>
              ProfessionalsBloc()..add(ProfessionalSelected(professionalId)),
        ),
        BlocProvider<ChatBloc>(
          create: (_) =>
              ChatBloc()..add(ChatOpened(professionalId: professionalId)),
        ),
      ],
      child: _DetailView(professionalId: professionalId, preview: preview),
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.professionalId, this.preview});

  final String professionalId;
  final Professional? preview;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    // Deferred a frame: the new bubble has not been laid out yet, so
    // maxScrollExtent is still the old value at the moment we are called.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final double target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: AppDuration.normal,
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _startCall(
    BuildContext context,
    Professional professional, {
    required bool withVideo,
  }) async {
    final ChatState chat = context.read<ChatBloc>().state;
    final String? conversationId = chat.conversationId;

    if (conversationId == null) {
      AppSnackbar.error(context, 'Still opening the conversation — try again.');
      return;
    }
    if (!SocketService.instance.isConnected) {
      AppSnackbar.error(
        context,
        'You are offline. Reconnect to start a call.',
      );
      return;
    }
    if (!professional.isAcceptingClients) {
      AppSnackbar.show(
        context,
        '${professional.firstName} is not taking new calls right now.',
      );
      return;
    }

    context.read<CallBloc>().add(
          CallDialRequested(
            conversationId: conversationId,
            peer: CallPeer(
              userId: professional.userId,
              name: professional.displayName,
              avatarUrl: professional.avatarUrl,
            ),
            withVideo: withVideo,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? selfId = context.watch<AppStore>().user?.id;

    return BlocBuilder<ProfessionalsBloc, ProfessionalsState>(
      builder: (BuildContext context, ProfessionalsState proState) {
        final Professional? professional = proState.selected ?? widget.preview;

        if (professional == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return BlocConsumer<ChatBloc, ChatState>(
          listenWhen: (ChatState a, ChatState b) =>
              a.messages.length != b.messages.length ||
              a.errorMessage != b.errorMessage,
          listener: (BuildContext context, ChatState chat) {
            if (chat.errorMessage != null) {
              AppSnackbar.error(context, chat.errorMessage!);
            }
            if (chat.messages.isNotEmpty) _scrollToBottom();
          },
          builder: (BuildContext context, ChatState chat) {
            return Scaffold(
              backgroundColor: palette.bg,
              appBar: _DetailAppBar(
                professional: professional,
                onVoiceCall: () =>
                    _startCall(context, professional, withVideo: false),
                onVideoCall: () =>
                    _startCall(context, professional, withVideo: true),
              ),
              body: GlowBackground(
                alignment: const Alignment(0, -0.95),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    children: <Widget>[
                      _AboutSection(professional: professional),

                      if (professional.certifications.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        PortfolioSectionHeader(
                          title: 'Certifications',
                          icon: Icons.verified_rounded,
                          count: professional.certifications.length,
                        ),
                        ...professional.certifications.map(
                          (Certification c) => CertificationTile(
                            certification: c,
                          ),
                        ),
                      ],

                      if (professional.transformations.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        PortfolioSectionHeader(
                          title: 'Client transformations',
                          icon: Icons.auto_graph_rounded,
                          count: professional.transformations.length,
                        ),
                        ...professional.transformations.map(
                          (ClientTransformation t) => TransformationCard(
                            transformation: t,
                          ),
                        ),
                      ],

                      if (professional.achievements.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        PortfolioSectionHeader(
                          title: 'Achievements',
                          icon: Icons.emoji_events_rounded,
                          count: professional.achievements.length,
                        ),
                        ...professional.achievements.map(
                          (Achievement a) => AchievementTile(achievement: a),
                        ),
                      ],

                      // ---- Chat ----------------------------------------
                      const SizedBox(height: AppSpacing.xl),
                      PortfolioSectionHeader(
                        title: 'Chat with ${professional.firstName}',
                        icon: Icons.forum_rounded,
                      ),

                      if (chat.isLoadingHistory)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.xl,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      // No conversation id means the thread never opened.
                      // Rendering the normal empty state there is a lie —
                      // the composer is disabled and nothing the user does
                      // will send. Offer the retry instead.
                      else if (chat.conversationId == null)
                        _ChatUnavailable(
                          message: chat.errorMessage ??
                              'Could not open this conversation.',
                          onRetry: () => context
                              .read<ChatBloc>()
                              .add(const ChatOpenRetried()),
                        )
                      else ...<Widget>[
                        if (chat.hasMore)
                          Center(
                            child: TextButton.icon(
                              onPressed: chat.isLoadingMore
                                  ? null
                                  : () => context
                                      .read<ChatBloc>()
                                      .add(const ChatHistoryRequested()),
                              icon: chat.isLoadingMore
                                  ? const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.history_rounded,
                                      size: AppSize.iconSm,
                                    ),
                              label: const Text('Load earlier messages'),
                            ),
                          ),

                        if (chat.isEmpty)
                          _ChatEmptyState(professional: professional)
                        else
                          ..._buildBubbles(context, chat, selfId),

                        if (chat.isPeerTyping) const TypingIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: ChatComposer(
                enabled: chat.isReady,
                hintText: 'Message ${professional.firstName}…',
                onChanged: (String text) =>
                    context.read<ChatBloc>().add(ChatComposerChanged(text)),
                onSend: (String text) {
                  context.read<ChatBloc>().add(ChatMessageSent(text));
                  _scrollToBottom();
                },
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildBubbles(
    BuildContext context,
    ChatState chat,
    String? selfId,
  ) {
    final List<Widget> widgets = <Widget>[];

    for (int i = 0; i < chat.messages.length; i++) {
      final ChatMessage message = chat.messages[i];
      final ChatMessage? next =
          i + 1 < chat.messages.length ? chat.messages[i + 1] : null;

      // The tail — pointed corner plus timestamp — goes on the last
      // message of each run, so a burst reads as one block.
      final bool showTail = next == null ||
          next.senderId != message.senderId ||
          next.kind != message.kind ||
          next.createdAt.difference(message.createdAt).inMinutes >= 2;

      widgets.add(
        ChatBubble(
          key: ValueKey<String>(message.clientId ?? message.id),
          message: message,
          isMine: message.isMine(selfId),
          showTail: showTail,
          onRetry: message.clientId == null
              ? null
              : () => context
                  .read<ChatBloc>()
                  .add(ChatMessageRetried(message.clientId!)),
        ),
      );
    }

    return widgets;
  }
}

// ---------------------------------------------------------------------------

class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar({
    required this.professional,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final Professional professional;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? avatar = AppConfig.resolveMediaUrl(professional.avatarUrl);

    return AppBar(
      toolbarHeight: 72,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: palette.border)),
      titleSpacing: 0,
      title: Row(
        children: <Widget>[
          SizedBox(
            height: 40,
            width: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                ClipOval(
                  child: avatar == null
                      ? Container(
                          decoration: const BoxDecoration(
                            gradient: AppColors.voltGradient,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            professional.initials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onVolt,
                            ),
                          ),
                        )
                      : Image.network(
                          avatar,
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                          errorBuilder: (_, __, ___) => Container(
                            color: palette.surfaceAlt,
                          ),
                        ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: PresenceDot(
                    isOnline: professional.isOnline,
                    size: 12,
                    ringColor: palette.surface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  professional.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium,
                ),
                PresenceLabel(
                  isOnline: professional.isOnline,
                  label: professional.presenceLabel,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        _CallAction(
          icon: Icons.call_rounded,
          tooltip: 'Voice call',
          onPressed: onVoiceCall,
        ),
        _CallAction(
          icon: Icons.videocam_rounded,
          tooltip: 'Video call',
          onPressed: onVideoCall,
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Material(
        color: palette.accent.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              height: 40,
              width: 40,
              child: Icon(icon, size: AppSize.iconMd, color: palette.accent),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.professional});

  final Professional professional;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(professional.headline, style: context.text.titleLarge),
        const SizedBox(height: AppSpacing.sm),

        Row(
          children: <Widget>[
            _Stat(
              value: professional.ratingCount == 0
                  ? '—'
                  : professional.ratingAverage.toStringAsFixed(1),
              label: professional.ratingCount == 0
                  ? 'No ratings'
                  : '${professional.ratingCount} ratings',
              icon: Icons.star_rounded,
              tint: AppColors.warning,
            ),
            _Stat(
              value: '${professional.yearsExperience}',
              label: 'Years',
              icon: Icons.workspace_premium_rounded,
            ),
            _Stat(
              value: '${professional.clientsCoached}',
              label: 'Clients',
              icon: Icons.groups_rounded,
            ),
            _Stat(
              value: professional.formattedRate,
              label: 'Per session',
              icon: Icons.payments_rounded,
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),
        Text(
          professional.bio,
          style: context.text.bodyMedium
              ?.copyWith(color: palette.textSecondary, height: 1.6),
        ),

        if (professional.specialities.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: professional.specialities
                .map(
                  (Speciality s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: AppRadius.rPill,
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(s.icon, size: 13, color: palette.accent),
                        const SizedBox(width: 4),
                        Text(
                          s.label,
                          style: context.text.bodySmall
                              ?.copyWith(color: palette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],

        if (professional.languages.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Icon(
                Icons.translate_rounded,
                size: AppSize.iconSm,
                color: palette.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  professional.languages.join(' · '),
                  style: context.text.bodySmall
                      ?.copyWith(color: palette.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    this.tint,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 15, color: tint ?? palette.accent),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.titleMedium),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall
                ?.copyWith(color: palette.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Shown when the thread could not be opened at all.
///
/// Distinct from the empty state on purpose: "say hello" next to a dead
/// composer reads as the app being broken in a way the user cannot name.
class _ChatUnavailable extends StatelessWidget {
  const _ChatUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Chat unavailable', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodySmall
                ?.copyWith(color: palette.textTertiary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: AppSize.iconSm),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.professional});

  final Professional professional;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.waving_hand_rounded,
            size: 28,
            color: palette.accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Say hello to ${professional.firstName}',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Ask about their approach, your goals, or book a call. '
            'Replies usually come within a few hours.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall
                ?.copyWith(color: palette.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }
}
