import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// One message.
///
/// Mine sit right on the accent, theirs left on the surface — the oldest
/// convention in messaging, and the reason a thread is readable at a
/// glance without reading a single word.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.message,
    required this.isMine,
    required this.showTail,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;
  final bool isMine;

  /// True for the last message in a run from the same sender — only that
  /// one gets the pointed corner and the timestamp.
  final bool showTail;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.kind == MessageKind.call) {
      return _CallEntry(message: message, isMine: isMine);
    }
    if (message.kind == MessageKind.system) {
      return _SystemEntry(message: message);
    }

    final AppPalette palette = context.palette;
    final bool failed = message.delivery == MessageDelivery.failed;

    final Widget bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: failed
            ? AppColors.danger.withValues(alpha: 0.16)
            : (isMine ? palette.accent : palette.surfaceAlt),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(isMine || !showTail ? AppRadius.md : 4),
          bottomRight: Radius.circular(!isMine || !showTail ? AppRadius.md : 4),
        ),
        border: isMine ? null : Border.all(color: palette.border),
      ),
      child: Text(
        message.body,
        style: context.text.bodyMedium?.copyWith(
          color: failed
              ? AppColors.danger
              : (isMine ? palette.onAccent : palette.textPrimary),
          height: 1.4,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: showTail ? AppSpacing.sm : 3),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (failed && onRetry != null)
            GestureDetector(onTap: onRetry, child: bubble)
          else
            bubble,
          if (showTail || failed) ...<Widget>[
            const SizedBox(height: 3),
            _MetaLine(message: message, isMine: isMine, onRetry: onRetry),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    if (message.delivery == MessageDelivery.failed) {
      return GestureDetector(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.refresh_rounded,
              size: 12,
              color: AppColors.danger,
            ),
            const SizedBox(width: 3),
            Text(
              'Not sent · tap to retry',
              style: context.text.bodySmall
                  ?.copyWith(color: AppColors.danger, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _timeOf(message.createdAt),
          style: context.text.bodySmall
              ?.copyWith(color: palette.textTertiary, fontSize: 11),
        ),
        if (isMine) ...<Widget>[
          const SizedBox(width: 4),
          _DeliveryTick(message: message),
        ],
      ],
    );
  }

  static String _timeOf(DateTime time) {
    final int hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'am' : 'pm'}';
  }
}

/// Sending → sent → read, as one or two ticks.
class _DeliveryTick extends StatelessWidget {
  const _DeliveryTick({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    if (message.delivery == MessageDelivery.sending) {
      return SizedBox(
        height: 10,
        width: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.4,
          valueColor: AlwaysStoppedAnimation<Color>(palette.textTertiary),
        ),
      );
    }

    // More than just the sender has read it.
    final bool read = message.readBy.length > 1;
    return Icon(
      read ? Icons.done_all_rounded : Icons.done_rounded,
      size: 13,
      color: read ? palette.accent : palette.textTertiary,
    );
  }
}

/// A call that happened, rendered inline so the thread is one timeline.
class _CallEntry extends StatelessWidget {
  const _CallEntry({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool missed = message.callOutcome == CallOutcome.missed ||
        message.callOutcome == CallOutcome.declined;

    final IconData icon = message.callWithVideo == false
        ? (missed ? Icons.phone_missed_rounded : Icons.phone_rounded)
        : (missed
            ? Icons.videocam_off_rounded
            : Icons.videocam_rounded);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: AppRadius.rPill,
            border: Border.all(
              color: missed
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: missed ? AppColors.danger : palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                message.body,
                style: context.text.bodySmall?.copyWith(
                  color: missed ? AppColors.danger : palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemEntry extends StatelessWidget {
  const _SystemEntry({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textTertiary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Three animated dots while the other person is typing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.md),
              topRight: Radius.circular(AppRadius.md),
              bottomRight: Radius.circular(AppRadius.md),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: palette.border),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(3, (int i) {
                  // Stagger each dot by a third of the cycle.
                  final double t = ((_controller.value + i * 0.22) % 1.0);
                  final double lift = t < 0.5 ? t * 2 : (1 - t) * 2;
                  return Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                    child: Transform.translate(
                      offset: Offset(0, -3 * lift),
                      child: Container(
                        height: 6,
                        width: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.textTertiary.withValues(
                            alpha: 0.5 + 0.5 * lift,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}
