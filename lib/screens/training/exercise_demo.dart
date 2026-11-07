import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/training_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'training_ui.dart';

class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({required this.exercise, super.key});

  final TrainingExercise exercise;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo> {
  VideoPlayerController? _player;
  bool _openingVideo = false;
  bool _videoFailed = false;
  int _imageAttempt = 0;

  bool get _playbackSupported =>
      kIsWeb ||
      const <TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.isCurrentOf(context);
    final player = _player;
    if (isCurrent == false && player != null && player.value.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _player == player && player.value.isPlaying) {
          unawaited(_togglePlayback(player));
        }
      });
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  Future<void> _play(TrainingMedia video) async {
    if (_openingVideo) return;
    final previous = _player;
    final player = VideoPlayerController.networkUrl(Uri.parse(video.url));
    setState(() {
      _player = player;
      _openingVideo = true;
      _videoFailed = false;
    });
    if (previous != null) unawaited(previous.dispose());
    try {
      await player.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || player != _player) return;
      if (ModalRoute.isCurrentOf(context) != false) await player.play();
    } on Object {
      if (!mounted || player != _player) return;
      setState(() {
        _player = null;
        _videoFailed = true;
      });
      unawaited(player.dispose());
    } finally {
      if (mounted) setState(() => _openingVideo = false);
    }
  }

  Future<void> _togglePlayback(VideoPlayerController player) async {
    try {
      if (player.value.isPlaying) {
        await player.pause();
      } else {
        if (player.value.position >= player.value.duration) {
          await player.seekTo(Duration.zero);
        }
        await player.play();
      }
    } on Object {
      if (!mounted || _player != player) return;
      setState(() {
        _player = null;
        _videoFailed = true;
      });
      unawaited(player.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final poster = exercise.poster ??
        exercise.media.where((media) => media.type == 'image').firstOrNull;
    final video =
        exercise.media.where((media) => media.type == 'video').firstOrNull;
    final player = _player;
    return SectionCard(
      title: 'Demonstration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (player != null && !_openingVideo)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: player,
              builder: (context, value, child) {
                if (value.hasError) {
                  return _preview(poster, video, videoFailed: true);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AspectRatio(aspectRatio: value.aspectRatio, child: child!),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: value.isPlaying
                              ? 'Pause demonstration'
                              : 'Play demonstration',
                          onPressed: () => unawaited(_togglePlayback(player)),
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            player,
                            allowScrubbing: true,
                          ),
                        ),
                      ],
                    ),
                    if (video?.attribution != null)
                      Text(video!.attribution!, style: context.text.bodySmall),
                  ],
                );
              },
              child: VideoPlayer(player),
            )
          else
            _preview(poster, video, videoFailed: _videoFailed),
        ],
      ),
    );
  }

  Widget _preview(
    TrainingMedia? poster,
    TrainingMedia? video, {
    required bool videoFailed,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (poster != null) ...<Widget>[
            ClipRRect(
              borderRadius: AppRadius.rMd,
              child: Image.network(
                poster.url,
                key: ValueKey<int>(_imageAttempt),
                width: double.infinity,
                height: 176,
                fit: BoxFit.contain,
                semanticLabel: '${widget.exercise.name} demonstration image',
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 176,
                        child: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Loading demonstration image',
                          ),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => Center(
                  child: TrainingNotice(
                    message: 'The demonstration image could not load.',
                    action: () async {
                      await NetworkImage(poster.url).evict();
                      if (mounted) setState(() => _imageAttempt++);
                    },
                    label: 'Retry image',
                  ),
                ),
              ),
            ),
            if (poster.attribution != null)
              Text(poster.attribution!, style: context.text.bodySmall),
          ],
          if (video == null && poster == null)
            const Text(
              'A demonstration is not available yet. Follow the instructions below.',
            ),
          if (video != null && !_playbackSupported)
            const Text(
              'Video playback is unavailable on this device. Follow the instructions below.',
            ),
          if (video != null && _playbackSupported) ...<Widget>[
            if (videoFailed)
              const Text(
                'The video could not play. The instructions are still available below.',
              ),
            if (_openingVideo)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading exercise video',
              )
            else
              TextButton.icon(
                onPressed: () => unawaited(_play(video)),
                icon: Icon(
                  videoFailed ? Icons.refresh : Icons.play_circle_outline,
                ),
                label: Text(videoFailed ? 'Retry video' : 'Play demonstration'),
              ),
          ],
        ],
      );
}
