import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/call/call_bloc.dart';
import '../models/call_models.dart';
import '../screens/call/call_screen.dart';
import '../screens/call/incoming_call_screen.dart';
import '../services/call_window_service.dart';

/// Puts the call UI above everything else.
///
/// An overlay rather than a route: a call can start from any screen, at
/// any moment, including from a push while the user is deep in a
/// navigation stack. Pushing a route would mean guessing which navigator
/// to push onto and unwinding it correctly afterwards — this simply draws
/// on top and disappears when the call ends, leaving the stack untouched.
class CallOverlay extends StatelessWidget {
  const CallOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallBloc, CallState>(
      listenWhen: (CallState a, CallState b) => a.phase != b.phase,
      listener: (BuildContext context, CallState state) {
        // Show over the lock screen and keep the screen awake for as long
        // as there is a call — and, just as importantly, stop doing both
        // the moment there is not. This is the only place that knows the
        // call UI is up, so it is the only place that can turn it off.
        unawaited(
          CallWindowService.instance.setCallActive(
            state.isActive || state.phase == CallPhase.ended,
          ),
        );

        if (state.phase != CallPhase.ended) return;

        // Hold the outcome on screen briefly — "Call declined" that
        // vanishes in a frame just reads as the call failing silently.
        Timer(const Duration(milliseconds: 1600), () {
          if (!context.mounted) return;
          final CallBloc bloc = context.read<CallBloc>();
          if (bloc.state.phase == CallPhase.ended) {
            bloc.add(const CallDismissed());
          }
        });
      },
      buildWhen: (CallState a, CallState b) =>
          a.phase != b.phase || a.isOutgoing != b.isOutgoing,
      builder: (BuildContext context, CallState state) {
        final bool showCallUi =
            state.isActive || state.phase == CallPhase.ended;

        return Stack(
          children: <Widget>[
            child,
            if (showCallUi)
              Positioned.fill(
                child: _CallSurface(
                  // Keyed by phase-group so answering an incoming call
                  // rebuilds into the in-call screen rather than trying to
                  // morph one into the other.
                  key: ValueKey<bool>(state.isRinging && !state.isOutgoing),
                  isIncoming: state.isRinging && !state.isOutgoing,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Swallows the Android back button for as long as it is on screen.
///
/// Neither of the obvious widgets works here, and both fail differently:
///
///  * `PopScope` governs only the route it sits inside. This surface is
///    drawn from `MaterialApp.builder` — above the Navigator, inside no
///    route at all — so a `PopScope` is silently inert and back would pop
///    whatever screen is hiding behind the call.
///  * `BackButtonListener` needs a `Router` ancestor and throws
///    "Router operation requested with a context that does not include a
///    Router" when there is none. This app uses plain `MaterialApp` with
///    `onGenerateRoute`, so there is no Router anywhere in the tree.
///
/// So it registers with `WidgetsBinding` directly — the same mechanism
/// `BackButtonDispatcher` is built on. `handlePopRoute` walks observers
/// in **reverse** registration order and stops at the first that returns
/// true; this one registers when a call starts, long after `WidgetsApp`
/// registered its own at launch, so it gets first refusal and only while
/// a call is up.
class _CallSurface extends StatefulWidget {
  const _CallSurface({required this.isIncoming, super.key});

  final bool isIncoming;

  @override
  State<_CallSurface> createState() => _CallSurfaceState();
}

class _CallSurfaceState extends State<_CallSurface>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back must not dismiss a live call — the hang-up button is the only
  /// exit, because it is the only thing that tears the media down.
  @override
  Future<bool> didPopRoute() async => true;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child:
          widget.isIncoming ? const IncomingCallScreen() : const CallScreen(),
    );
  }
}
