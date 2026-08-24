import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Asks the host activity to show the call over the lock screen.
///
/// Android only. iOS gets this for free: CallKit owns the incoming-call
/// screen and the system handles the lock screen itself, so every method
/// here is a no-op there rather than a platform exception.
///
/// The flags are deliberately *not* in the manifest — see MainActivity.kt
/// for why. That makes this class the only thing standing between "the
/// phone rings and you can answer it" and "the phone rings and you have to
/// unlock first", so it must fail quietly rather than take the call down
/// with it: a missing channel means an older build of the Android host,
/// not a broken call.
class CallWindowService {
  CallWindowService._();

  static final CallWindowService instance = CallWindowService._();

  static const MethodChannel _channel =
      MethodChannel('com.fitnessapp/call_window');

  bool _active = false;

  /// True while the call window flags are on.
  bool get isActive => _active;

  Future<void> setCallActive(bool active) async {
    if (!Platform.isAndroid) return;
    if (_active == active) return;
    _active = active;

    try {
      await _channel.invokeMethod<void>(
        'setCallActive',
        <String, dynamic>{'active': active},
      );
    } on MissingPluginException {
      developer.log(
        'call window channel not registered — lock screen bypass is off',
        name: 'call',
      );
    } catch (error) {
      developer.log('call window flags failed: $error', name: 'call');
    }
  }

  /// Whether the keyguard is up right now. Used to decide whether
  /// answering should go straight into the call or ask for an unlock
  /// first.
  Future<bool> isDeviceLocked() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isDeviceLocked') ?? false;
    } catch (_) {
      return false;
    }
  }
}
