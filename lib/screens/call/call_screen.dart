import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../blocs/call/call_bloc.dart';
import '../../models/call_models.dart';
import '../../theme/app_theme.dart';

/// The in-call surface.
///
/// Remote video fills the screen, local video is a draggable thumbnail,
/// and the controls fade out during a video call so the picture is not
/// permanently obscured by buttons nobody is pressing.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _controlsVisible = true;

  /// Local preview position, as a fraction of the screen.
  Alignment _pipAlignment = const Alignment(0.88, -0.78);

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocBuilder<CallBloc, CallState>(
      builder: (BuildContext context, CallState state) {
        final CallBloc bloc = context.read<CallBloc>();
        final bool showRemoteVideo = state.withVideo &&
            state.hasRemoteVideo &&
            state.phase == CallPhase.connected;

        return Scaffold(
          backgroundColor: AppColors.darkBg,
          body: GestureDetector(
            // Tap anywhere to bring the controls back.
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ---- Remote video, or the peer's identity ----------------
                if (showRemoteVideo)
                  RTCVideoView(
                    bloc.remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                else
                  _PeerBackdrop(state: state),

                // ---- Local preview --------------------------------------
                if (state.withVideo && state.isCameraEnabled)
                  _LocalPreview(
                    renderer: bloc.localRenderer,
                    alignment: _pipAlignment,
                    mirror: state.isFrontCamera,
                    onMoved: (Alignment alignment) =>
                        setState(() => _pipAlignment = alignment),
                  ),

                // ---- Top bar --------------------------------------------
                AnimatedOpacity(
                  duration: AppDuration.normal,
                  opacity: _controlsVisible || !showRemoteVideo ? 1 : 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          if (showRemoteVideo) ...<Widget>[
                            Text(
                              state.peer?.name ?? 'Call',
                              style: context.text.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              state.statusLabel,
                              style: context.text.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                          if (!state.turnAvailable &&
                              state.phase == CallPhase.connecting)
                            const _TurnWarning(),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---- Controls -------------------------------------------
                AnimatedPositioned(
                  duration: AppDuration.normal,
                  curve: Curves.easeOut,
                  left: 0,
                  right: 0,
                  bottom: _controlsVisible || !showRemoteVideo ? 0 : -180,
                  child: _CallControls(
                    state: state,
                    onToggleMic: () => bloc.add(const CallMicToggled()),
                    onToggleCamera: () => bloc.add(const CallCameraToggled()),
                    onToggleSpeaker: () => bloc.add(const CallSpeakerToggled()),
                    onSwitchCamera: () => bloc.add(const CallCameraSwitched()),
                    onHangUp: () => bloc.add(const CallHangUpRequested()),
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

/// Shown while there is no remote video: during a voice call, before the
/// far end's stream arrives, or when they turn their camera off.
class _PeerBackdrop extends StatelessWidget {
  const _PeerBackdrop({required this.state});

  final CallState state;

  @override
  Widget build(BuildContext context) {
    final CallPeer? peer = state.peer;

    return Container(
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
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            const Spacer(flex: 2),
            _PulsingAvatar(
              initials: peer?.initials ?? '?',
              // Only pulse while waiting — a pulse during a connected call
              // reads as a problem.
              animate: state.phase == CallPhase.dialling ||
                  state.phase == CallPhase.connecting ||
                  state.phase == CallPhase.reconnecting,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              peer?.name ?? 'Call',
              style: context.text.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.statusLabel,
              style: context.text.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: AppSpacing.pageWide,
                child: Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall
                      ?.copyWith(color: AppColors.warning),
                ),
              ),
            ],
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.initials, required this.animate});

  final String initials;
  final bool animate;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

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
        return SizedBox(
          height: 200,
          width: 200,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (widget.animate)
                for (int ring = 0; ring < 2; ring++)
                  _Ring(progress: (_controller.value + ring * 0.5) % 1.0),
              Container(
                height: 116,
                width: 116,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.voltGradient,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.initials,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onVolt,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final double size = 116 + progress * 84;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.volt.withValues(alpha: (1 - progress) * 0.4),
          width: 2,
        ),
      ),
    );
  }
}

/// Draggable local camera preview.
class _LocalPreview extends StatelessWidget {
  const _LocalPreview({
    required this.renderer,
    required this.alignment,
    required this.mirror,
    required this.onMoved,
  });

  final RTCVideoRenderer renderer;
  final Alignment alignment;
  final bool mirror;
  final ValueChanged<Alignment> onMoved;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: GestureDetector(
          onPanUpdate: (DragUpdateDetails details) {
            final Size size = MediaQuery.sizeOf(context);
            onMoved(
              Alignment(
                (alignment.x + details.delta.dx / (size.width / 2))
                    .clamp(-0.92, 0.92),
                (alignment.y + details.delta.dy / (size.height / 2))
                    .clamp(-0.82, 0.68),
              ),
            );
          },
          child: Container(
            height: 168,
            width: 112,
            decoration: BoxDecoration(
              borderRadius: AppRadius.rMd,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: RTCVideoView(
              renderer,
              // The front camera is mirrored so it behaves like a mirror;
              // the rear camera must not be, or text reads backwards.
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.state,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleSpeaker,
    required this.onSwitchCamera,
    required this.onHangUp,
  });

  final CallState state;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _ControlButton(
                    icon: state.isMicEnabled
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                    label: state.isMicEnabled ? 'Mute' : 'Unmute',
                    isActive: !state.isMicEnabled,
                    onPressed: onToggleMic,
                  ),
                  if (state.withVideo)
                    _ControlButton(
                      icon: state.isCameraEnabled
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: state.isCameraEnabled ? 'Camera' : 'Camera off',
                      isActive: !state.isCameraEnabled,
                      onPressed: onToggleCamera,
                    ),
                  _ControlButton(
                    icon: state.isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    label: state.isSpeakerOn ? 'Speaker' : 'Earpiece',
                    isActive: false,
                    onPressed: onToggleSpeaker,
                  ),
                  if (state.withVideo)
                    _ControlButton(
                      icon: Icons.cameraswitch_rounded,
                      label: 'Flip',
                      isActive: false,
                      onPressed: onSwitchCamera,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _HangUpButton(onPressed: onHangUp),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String label;

  /// True when the control is in its "engaged" state — muted, camera off.
  /// Inverted colouring makes that unmistakable at a glance.
  final bool isActive;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 56,
              width: 56,
              child: Icon(
                icon,
                size: AppSize.iconLg,
                color: isActive ? AppColors.darkBg : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.danger,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const SizedBox(
          height: 62,
          width: 148,
          child: Icon(
            Icons.call_end_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _TurnWarning extends StatelessWidget {
  const _TurnWarning();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.16),
          borderRadius: AppRadius.rSm,
        ),
        child: Text(
          'No TURN relay configured — this call may not connect on some '
          'networks.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall
              ?.copyWith(color: AppColors.warning, fontSize: 11),
        ),
      ),
    );
  }
}
