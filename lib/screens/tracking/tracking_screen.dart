import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/tracking/tracking_recorder_cubit.dart';
import '../../models/tracking_models.dart';
import '../../services/tracking_recorder.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/section_card.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({this.recorder, super.key});

  /// Injectable for device-independent tests. The production tab uses the
  /// Android platform recorder.
  final TrackingRecorder? recorder;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  late final TrackingRecorderCubit _cubit = TrackingRecorderCubit(
    recorder: widget.recorder ?? PlatformTrackingRecorder(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_cubit.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_cubit.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cubit.close());
    super.dispose();
  }

  void _feedback(BuildContext context, TrackingRecorderState state) {
    if (state.error != null) {
      AppSnackbar.error(context, state.error!);
    } else if (state.notice != null) {
      AppSnackbar.success(context, state.notice!);
    }
  }

  Future<void> _confirmStop() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Finish workout?'),
        content: const Text(
          'The route recorded so far will stay safely stored on this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_cubit.stop());
  }

  Future<void> _confirmDiscard() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
          'This permanently removes the current session and every recorded GPS point.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_cubit.discard());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TrackingRecorderCubit>.value(
      value: _cubit,
      child: BlocListener<TrackingRecorderCubit, TrackingRecorderState>(
        listenWhen:
            (TrackingRecorderState before, TrackingRecorderState after) =>
                before.revision != after.revision,
        listener: _feedback,
        child: Scaffold(
          backgroundColor: context.palette.bg,
          body: GlowBackground(
            alignment: const Alignment(0, -0.95),
            child: SafeArea(
              child: BlocBuilder<TrackingRecorderCubit, TrackingRecorderState>(
                builder: (BuildContext context, TrackingRecorderState state) {
                  return RefreshIndicator(
                    onRefresh: () => _cubit.refresh(showBusy: true),
                    color: context.palette.accent,
                    backgroundColor: context.palette.surfaceHigh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.huge,
                      ),
                      children: <Widget>[
                        Text('Tracking', style: context.text.headlineMedium),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Record an outdoor workout directly with your phone.',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (!state.initialized)
                          const _LoadingCard()
                        else if (state.session.isActive)
                          _LiveRecorderCard(
                            state: state,
                            onPause: _cubit.pause,
                            onResume: _cubit.resume,
                            onStop: _confirmStop,
                            onDiscard: _confirmDiscard,
                          )
                        else
                          _RecorderReadyCard(
                            state: state,
                            onStart: _cubit.start,
                            onRequestPermissions: _cubit.requestPermissions,
                            onOpenAppSettings: _cubit.openAppSettings,
                            onOpenLocationSettings: _cubit.openLocationSettings,
                          ),
                        const SizedBox(height: AppSpacing.md),
                        const _PrivacyCard(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecorderReadyCard extends StatelessWidget {
  const _RecorderReadyCard({
    required this.state,
    required this.onStart,
    required this.onRequestPermissions,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final TrackingRecorderState state;
  final VoidCallback onStart;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final TrackingPermissionSnapshot permission = state.permission;
    if (!permission.supported) {
      return const _MessageCard(
        icon: Icons.phone_android_rounded,
        title: 'Android recorder',
        message:
            'Route recording is currently available on Android. Other tracking platforms will be added separately.',
      );
    }
    if (permission.location == TrackingLocationPermission.notRequested) {
      return _PermissionRationaleCard(
        busy: state.busy,
        buttonLabel: 'Continue',
        onPressed: onRequestPermissions,
      );
    }
    if (!permission.locationServicesEnabled) {
      return _MessageCard(
        icon: Icons.location_disabled_rounded,
        title: 'Turn on phone location',
        message:
            'Location services are off. Turn them on, then return here to start recording.',
        buttonLabel: 'Open location settings',
        busy: state.busy,
        onPressed: onOpenLocationSettings,
      );
    }
    if (permission.needsAppSettings) {
      final bool approximate =
          permission.location == TrackingLocationPermission.approximate;
      return _MessageCard(
        icon: Icons.gps_fixed_rounded,
        title: approximate
            ? 'Precise location is required'
            : 'Permission is blocked',
        message: approximate
            ? 'Approximate location cannot produce a trustworthy route. Enable precise location for Fitness App in system settings.'
            : 'Enable location and workout notifications in system settings to record safely with the screen off.',
        buttonLabel: 'Open app settings',
        busy: state.busy,
        onPressed: onOpenAppSettings,
      );
    }
    if (!permission.hasPreciseLocation || !permission.hasNotifications) {
      return _PermissionRationaleCard(
        busy: state.busy,
        buttonLabel: 'Try again',
        onPressed: onRequestPermissions,
      );
    }

    return SectionCard(
      gradient: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: context.palette.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_run_rounded,
              color: context.palette.accent,
              size: AppSize.iconLg,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Ready for an outdoor workout?',
            style: context.text.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The timer begins after GPS settles to a precise fix.',
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.busy ? null : onStart,
              icon: state.busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Start outdoor workout'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRationaleCard extends StatelessWidget {
  const _PermissionRationaleCard({
    required this.busy,
    required this.buttonLabel,
    required this.onPressed,
  });

  final bool busy;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Before your first workout',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Allow precise location', style: context.text.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Fitness App uses location only after you start a workout and stops when you finish or discard it. A persistent notification shows that recording is active, including while the screen is off.',
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _PermissionFact(
            icon: Icons.route_rounded,
            text: 'GPS points are saved continuously on this device.',
          ),
          const _PermissionFact(
            icon: Icons.notifications_active_outlined,
            text: 'The ongoing notification shows duration and distance.',
          ),
          const _PermissionFact(
            icon: Icons.no_accounts_outlined,
            text: 'Continuous background-location permission is not requested.',
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onPressed,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionFact extends StatelessWidget {
  const _PermissionFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppSize.iconSm, color: context.palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

class _LiveRecorderCard extends StatelessWidget {
  const _LiveRecorderCard({
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onDiscard,
  });

  final TrackingRecorderState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onDiscard;

  String _duration(Duration value) {
    final int hours = value.inHours;
    final int minutes = value.inMinutes.remainder(60);
    final int seconds = value.inSeconds.remainder(60);
    final String tail = '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
    return hours == 0 ? tail : '$hours:$tail';
  }

  @override
  Widget build(BuildContext context) {
    final TrackingSessionSnapshot session = state.session;
    final String status = switch (session.status) {
      TrackingSessionStatus.acquiring => 'Acquiring GPS',
      TrackingSessionStatus.paused => 'Paused',
      TrackingSessionStatus.recording => 'Recording',
      TrackingSessionStatus.idle => 'Ready',
    };
    final Color statusColor = session.isPaused
        ? AppColors.warning
        : session.isAcquiring
            ? context.palette.textSecondary
            : AppColors.success;

    return SectionCard(
      gradient: true,
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                status.toUpperCase(),
                style: context.text.labelSmall?.copyWith(color: statusColor),
              ),
            ],
          ),
          if (session.isAcquiring) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Keep the phone still with a clear view of the sky.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          ] else ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _duration(session.elapsed),
              style: context.text.displaySmall?.copyWith(
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: _LiveMetric(
                    label: 'Distance',
                    value: (session.distanceM / 1000).toStringAsFixed(2),
                    unit: 'km',
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: context.palette.border,
                ),
                Expanded(
                  child: _LiveMetric(
                    label: 'GPS points',
                    value: '${session.pointCount}',
                    unit: 'saved',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.busy || session.isAcquiring
                      ? null
                      : session.isPaused
                          ? onResume
                          : onPause,
                  icon: Icon(
                    session.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  label: Text(session.isPaused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.busy || session.isAcquiring ? null : onStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Finish'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: state.busy ? null : onDiscard,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(session.isAcquiring ? 'Cancel workout' : 'Discard'),
          ),
        ],
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(label, style: context.text.labelSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: context.text.headlineSmall),
        Text(
          unit,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, color: context.palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Step 1 stores unfinished and completed routes only in local SQLite. Cloud upload and sharing are not enabled yet.',
              style: context.text.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.busy = false,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 38, color: context.palette.accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (buttonLabel != null && onPressed != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onPressed,
                child: Text(buttonLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
