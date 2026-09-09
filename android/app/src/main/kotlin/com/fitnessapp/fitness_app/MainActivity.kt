package com.fitnessapp.fitness_app

import android.Manifest
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine, and owns one thing Flutter cannot do itself:
 * showing the app over the lock screen while a call is up.
 *
 * The manifest deliberately does not set `android:showWhenLocked` /
 * `android:turnScreenOn`. Those are activity-lifetime flags — with them
 * set, pressing power on a locked phone that has this app in the
 * foreground reveals the user's profile to whoever is holding it. Instead
 * the flags go on when a call starts and come off when it ends, so the
 * lock screen is bypassed for exactly the window where that is the
 * expected behaviour of a phone that is ringing.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.fitnessapp/call_window"

        const val TRACKING_CHANNEL = "com.fitnessapp/tracking_recorder"
        const val TRACKING_PERMISSION_REQUEST = 2208

        /** Must match `default_notification_channel_id` in the manifest. */
        const val CALL_CHANNEL_ID = "fitness_app_calls"
    }

    private var trackingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createCallNotificationChannel()
    }

    /**
     * Creates the high-importance channel calls are announced on.
     *
     * The manifest points FCM's default channel at this id. If nothing
     * ever creates it, Android quietly files those notifications under
     * "Miscellaneous" at low importance — which means an incoming call
     * arrives silently, with no heads-up and no sound. Creating a channel
     * is idempotent, so running this on every launch costs nothing;
     * changing importance later, however, is ignored by the OS once the
     * channel exists, so bump the id if that ever needs to change.
     */
    private fun createCallNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
        if (manager.getNotificationChannel(CALL_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Calls from your coach"
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            setSound(
                android.media.RingtoneManager.getDefaultUri(
                    android.media.RingtoneManager.TYPE_RINGTONE,
                ),
                AudioAttributes.Builder()
                    // USAGE_NOTIFICATION_RINGTONE, not USAGE_NOTIFICATION:
                    // the ringtone stream is the one that stays audible
                    // under Do Not Disturb's "allow calls" exception.
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setCallActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    // Window flags must be touched on the UI thread; a
                    // MethodChannel handler already runs there, but the
                    // call can arrive while the activity is being torn
                    // down, so post it rather than assuming.
                    runOnUiThread { setShowOverLockScreen(active) }
                    result.success(null)
                }
                "isDeviceLocked" -> result.success(isDeviceLocked())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRACKING_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "permissionStatus" -> result.success(trackingPermissionState())
                "requestPermissions" -> requestTrackingPermissions(result)
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "openLocationSettings" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(null)
                }
                "getSession" -> result.success(TrackingStore.currentMap(this))
                "getSessionPoints" -> {
                    val sessionId = call.argument<String>("sessionId")?.trim()
                    if (sessionId.isNullOrEmpty()) {
                        result.error(
                            "BAD_SESSION_ID",
                            "A session id is required to read route points.",
                            null,
                        )
                    } else {
                        result.success(TrackingDatabase.get(this).listPoints(sessionId))
                    }
                }
                "start" -> dispatchTrackingCommand(TrackingService.ACTION_START, result)
                "pause" -> dispatchTrackingCommand(TrackingService.ACTION_PAUSE, result)
                "resume" -> dispatchTrackingCommand(TrackingService.ACTION_RESUME, result)
                "stop" -> dispatchTrackingCommand(TrackingService.ACTION_STOP, result)
                "discard" -> dispatchTrackingCommand(TrackingService.ACTION_DISCARD, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestTrackingPermissions(result: MethodChannel.Result) {
        if (trackingPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_ACTIVE",
                "A permission request is already open.",
                null,
            )
            return
        }

        val permissions = mutableListOf<String>()
        val needsLocation =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED
        if (needsLocation) {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
            permissions += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        val needsNotifications =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        if (needsNotifications) permissions += Manifest.permission.POST_NOTIFICATIONS

        if (permissions.isEmpty()) {
            result.success(trackingPermissionState())
            return
        }

        TrackingStore.markPermissionRequests(
            this,
            location = needsLocation,
            notifications = needsNotifications,
        )
        trackingPermissionResult = result
        requestPermissions(permissions.toTypedArray(), TRACKING_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != TRACKING_PERMISSION_REQUEST) return
        trackingPermissionResult?.success(trackingPermissionState())
        trackingPermissionResult = null
    }

    private fun trackingPermissionState(): Map<String, Any> {
        val fine =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val coarse =
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val location = when {
            fine -> "precise"
            coarse -> "approximate"
            !TrackingStore.hasAskedLocation(this) -> "notRequested"
            shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) ->
                "denied"
            else -> "deniedForever"
        }

        val notifications = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            "notRequired"
        } else if (
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else if (!TrackingStore.hasAskedNotifications(this)) {
            "notRequested"
        } else if (
            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
        ) {
            "denied"
        } else {
            "deniedForever"
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        val locationEnabled =
            manager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
        return mapOf(
            "supported" to true,
            "locationServicesEnabled" to locationEnabled,
            "location" to location,
            "notifications" to notifications,
        )
    }

    private fun dispatchTrackingCommand(action: String, result: MethodChannel.Result) {
        if (action == TrackingService.ACTION_START) {
            val permission = trackingPermissionState()
            if (permission["location"] != "precise") {
                result.error(
                    "PRECISE_LOCATION_REQUIRED",
                    "Allow precise location before starting a workout.",
                    null,
                )
                return
            }
            if (permission["locationServicesEnabled"] != true) {
                result.error(
                    "LOCATION_SERVICES_DISABLED",
                    "Turn on phone location before starting a workout.",
                    null,
                )
                return
            }
            if (permission["notifications"] !in setOf("granted", "notRequired")) {
                result.error(
                    "NOTIFICATIONS_REQUIRED",
                    "Allow workout notifications before starting a workout.",
                    null,
                )
                return
            }
        } else if (TrackingStore.read(this) == null) {
            result.error("NO_ACTIVE_WORKOUT", "There is no active workout.", null)
            return
        }

        val intent = Intent(this, TrackingService::class.java).setAction(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        // Service commands execute on this same main looper immediately after
        // the channel callback returns. Reply once the persisted state settles.
        Handler(Looper.getMainLooper()).postDelayed({ result.success(null) }, 80)
    }

    private fun isDeviceLocked(): Boolean {
        val keyguard =
            getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return keyguard?.isKeyguardLocked ?: false
    }

    private fun setShowOverLockScreen(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            // The modern API. setShowWhenLocked also dismisses a
            // *non-secure* keyguard; a PIN or biometric lock still has to
            // be satisfied before the user reaches anything else, which is
            // the behaviour we want — the call is answerable, the rest of
            // the app is not.
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            @Suppress("DEPRECATION")
            val flags =
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            if (show) {
                window.addFlags(flags)
            } else {
                window.clearFlags(flags)
            }
        }

        // Keeping the screen on is separate from unlocking it: without
        // this the display times out mid-call and the user has to keep
        // tapping to see the other person.
        if (show) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onDestroy() {
        // A crash or a kill mid-call must not leave the flags set for the
        // next launch. They are per-activity, so this is belt and braces —
        // but the failure mode it guards against is "the app shows over
        // your lock screen forever", which is worth two lines.
        setShowOverLockScreen(false)
        trackingPermissionResult?.error(
            "ACTIVITY_CLOSED",
            "The permission screen closed before it completed.",
            null,
        )
        trackingPermissionResult = null
        super.onDestroy()
    }
}
