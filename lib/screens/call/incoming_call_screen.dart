import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/call/call_bloc.dart';
import '../../models/call_models.dart';
import '../../theme/app_theme.dart';

/// In-app incoming call.
///
/// The native ringer (CallKit / a full-screen intent) covers the case
/// where the app is backgrounded. This is what shows when the app is
/// already open, where a system call screen would be jarring and would
/// hide the conversation the user is in the middle of.
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CallBloc, CallState>(
      builder: (BuildContext context, CallState state) {
        final CallBloc bloc = context.read<CallBloc>();
        final CallPeer? peer = state.peer;

        return Scaffold(
          backgroundColor: AppColors.darkBg,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  AppColors.darkSurfaceHigh,
                  AppColors.darkBg,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 2),

                  _RingingAvatar(initials: peer?.initials ?? '?'),

                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    peer?.name ?? 'Unknown caller',
                    style: context.text.displaySmall
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        state.withVideo
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        size: AppSize.iconSm,
                        color: AppColors.volt,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        state.withVideo
                            ? 'Incoming video call'
                            : 'Incoming voice call',
                        style: context.text.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(flex: 3),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.huge,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _AnswerButton(
                          icon: Icons.call_end_rounded,
                          color: AppColors.danger,
                          label: 'Decline',
                          onPressed: () =>
                              bloc.add(const CallDeclineRequested()),
                        ),
                        _AnswerButton(
                          icon: state.withVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          color: AppColors.success,
                          label: 'Answer',
                          // The one control that should be impossible to
                          // miss in a hurry.
                          isPrimary: true,
                          onPressed: () =>
                              bloc.add(const CallAcceptRequested()),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.huge),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingingAvatar extends StatefulWidget {
  const _RingingAvatar({required this.initials});

  final String initials;

  @override
  State<_RingingAvatar> createState() => _RingingAvatarState();
}

class _RingingAvatarState extends State<_RingingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // A gentle breathing scale, not a bounce — this can be on screen
        // for 45 seconds and anything sharper becomes irritating fast.
        final double scale =
            1 + 0.035 * math.sin(_controller.value * math.pi);

        return Transform.scale(
          scale: scale,
          child: Container(
            height: 132,
            width: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.voltGradient,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.volt.withValues(
                    alpha: 0.18 + 0.14 * _controller.value,
                  ),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              widget.initials,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: AppColors.onVolt,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final double size = isPrimary ? 76 : 68;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: size,
              width: size,
              child: Icon(icon, color: Colors.white, size: size * 0.42),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
