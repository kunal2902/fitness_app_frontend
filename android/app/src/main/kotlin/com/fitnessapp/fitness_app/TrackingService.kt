package com.fitnessapp.fitness_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.UUID

class TrackingService : Service(), LocationListener {
    companion object {
        const val ACTION_START = "com.fitnessapp.tracking.START"
        const val ACTION_PAUSE = "com.fitnessapp.tracking.PAUSE"
        const val ACTION_RESUME = "com.fitnessapp.tracking.RESUME"
        const val ACTION_STOP = "com.fitnessapp.tracking.STOP"
        const val ACTION_DISCARD = "com.fitnessapp.tracking.DISCARD"

        private const val CHANNEL_ID = "fitness_app_workout_tracking"
        private const val NOTIFICATION_ID = 2207
        private const val LIVE_ACCURACY_LIMIT_M = 30f
    }

    private lateinit var locationManager: LocationManager
    private lateinit var database: TrackingDatabase
    private val handler = Handler(Looper.getMainLooper())
    private var activeProvider: String? = null
    private var shuttingDown = false

    private val tick = object : Runnable {
        override fun run() {
            val state = TrackingStore.read(this@TrackingService)
            if (state == null || shuttingDown) return
            // Self-healing: if location was toggled off and on, or the provider
            // changed, this re-subscribes. It is a no-op otherwise.
            syncLocationUpdates()
            notifyState(state)
            handler.postDelayed(this, 1_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        database = TrackingDatabase.get(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        var state = TrackingStore.read(this)

        if (action == ACTION_START) shuttingDown = false

        if (action == ACTION_START && state == null) {
            val now = System.currentTimeMillis()
            val id = UUID.randomUUID().toString()
            database.createSession(id, now)
            state = TrackingStore.begin(this, id, now)
        }

        if (state == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (!startInForeground(state)) {
            // Android 12+ can refuse a background foreground-service start, and
            // Android 14+ throws when the permission behind the `location`
            // service type has been revoked. Park the workout rather than
            // crash: every point so far is already on disk, and the journal
            // lets the user resume it.
            if (state.status == "acquiring") {
                // Nothing was recorded yet, so leave no orphan the user has to
                // clear before starting again.
                database.discardSession(state.id)
                TrackingStore.clear(this)
            } else {
                val parked = TrackingStore.pause(this, System.currentTimeMillis())
                if (parked != null) database.updateSession(parked)
            }
            handler.removeCallbacks(tick)
            stopLocationUpdates()
            stopSelf()
            return START_NOT_STICKY
        }
        when (action) {
            ACTION_PAUSE -> pauseSession()
            ACTION_RESUME -> resumeSession()
            ACTION_STOP -> finishSession()
            ACTION_DISCARD -> discardSession()
            ACTION_START, null -> syncLocationUpdates()
        }

        if (!shuttingDown) {
            handler.removeCallbacks(tick)
            handler.post(tick)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onLocationChanged(location: Location) {
        val before = TrackingStore.read(this) ?: return
        if (before.status != "acquiring" && before.status != "recording") return

        val isMock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            @Suppress("DEPRECATION")
            location.isFromMockProvider
        }
        val accepted =
            location.hasAccuracy() &&
                location.accuracy in 0.1f..LIVE_ACCURACY_LIMIT_M &&
                !isMock
        // Scoped to the current segment, so the first accepted fix after a
        // resume has nothing to extend and the pause gap is never bridged.
        val previous =
            if (accepted) {
                database.lastAcceptedPoint(before.id, before.segmentIndex)
            } else {
                null
            }
        val capturedAt = location.time.takeIf { it > 0 } ?: System.currentTimeMillis()

        database.insertPoint(
            sessionId = before.id,
            capturedAt = capturedAt,
            latitude = location.latitude,
            longitude = location.longitude,
            // Null, not 0.0: a missing altitude read as sea level would give
            // Step 2's elevation profile a cliff at every gap.
            altitudeM = if (location.hasAltitude()) location.altitude else null,
            accuracyM = if (location.hasAccuracy()) location.accuracy else 0f,
            speedMps = if (location.hasSpeed()) location.speed.coerceAtLeast(0f) else 0f,
            bearingDegrees = if (location.hasBearing()) location.bearing else 0f,
            acceptedForLiveDistance = accepted,
            isMock = isMock,
            segment = before.segmentIndex,
        )

        var state = before
        if (state.status == "acquiring" && accepted) {
            state = TrackingStore.startFromFix(this, System.currentTimeMillis()) ?: state
        }

        var distance = state.distanceM
        if (state.status == "recording" && accepted && previous != null) {
            val result = FloatArray(1)
            Location.distanceBetween(
                previous.latitude,
                previous.longitude,
                location.latitude,
                location.longitude,
                result,
            )
            distance += result[0].toDouble().coerceAtLeast(0.0)
        }
        state = TrackingStore.updateMetrics(
            this,
            distanceM = distance,
            pointCount = state.pointCount + 1,
        ) ?: state
        database.updateSession(state)
        notifyState(state)
    }

    override fun onProviderEnabled(provider: String) {
        syncLocationUpdates()
    }

    override fun onProviderDisabled(provider: String) {
        if (provider == activeProvider) stopLocationUpdates()
        syncLocationUpdates()
        notifyState(TrackingStore.read(this) ?: return)
    }

    private fun pauseSession() {
        val next = TrackingStore.pause(this, System.currentTimeMillis()) ?: return
        stopLocationUpdates()
        database.updateSession(next)
        notifyState(next)
    }

    private fun resumeSession() {
        val next = TrackingStore.resume(this, System.currentTimeMillis()) ?: return
        database.updateSession(next)
        syncLocationUpdates()
        notifyState(next)
    }

    private fun finishSession() {
        val now = System.currentTimeMillis()
        val finished = TrackingStore.finish(this, now) ?: return
        if (finished.startedAt == null) {
            database.discardSession(finished.id)
        } else {
            database.completeSession(finished, now)
        }
        TrackingStore.clear(this)
        shutDown()
    }

    private fun discardSession() {
        val state = TrackingStore.read(this) ?: return
        database.discardSession(state.id)
        TrackingStore.clear(this)
        shutDown()
    }

    private fun shutDown() {
        shuttingDown = true
        handler.removeCallbacks(tick)
        stopLocationUpdates()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun syncLocationUpdates() {
        val state = TrackingStore.read(this) ?: return
        if (state.status != "acquiring" && state.status != "recording") {
            stopLocationUpdates()
            return
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stopLocationUpdates()
            return
        }

        val provider = when {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            stopLocationUpdates()
            return
        }
        if (provider == activeProvider) return

        stopLocationUpdates()
        try {
            locationManager.requestLocationUpdates(
                provider,
                1_000L,
                0f,
                this,
                Looper.getMainLooper(),
            )
            activeProvider = provider
        } catch (_: SecurityException) {
            activeProvider = null
        }
    }

    private fun stopLocationUpdates() {
        if (activeProvider == null) return
        try {
            locationManager.removeUpdates(this)
        } catch (_: SecurityException) {
            // Permission may have been revoked while the service was active.
        }
        activeProvider = null
    }

    /** Returns false when the platform refused the promotion. */
    private fun startInForeground(state: ActiveTrackingSession): Boolean {
        return try {
            val notification = buildNotification(state)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun notifyState(state: ActiveTrackingSession) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(state))
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(state: ActiveTrackingSession): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Workout recording")
            .setContentText(notificationText(state))
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)

        when (state.status) {
            "recording" -> {
                builder.addAction(action("Pause", ACTION_PAUSE, 1))
                builder.addAction(action("Finish", ACTION_STOP, 2))
            }
            "paused" -> {
                builder.addAction(action("Resume", ACTION_RESUME, 3))
                builder.addAction(action("Finish", ACTION_STOP, 2))
            }
            else -> builder.addAction(action("Cancel", ACTION_DISCARD, 4))
        }
        return builder.build()
    }

    private fun action(label: String, intentAction: String, requestCode: Int): Notification.Action {
        val intent = Intent(this, TrackingService::class.java).setAction(intentAction)
        val pending = PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(0, label, pending).build()
    }

    private fun notificationText(state: ActiveTrackingSession): String {
        if (state.status == "acquiring") return "Acquiring a precise GPS fix…"
        val elapsed = formatDuration(state.elapsedAt(System.currentTimeMillis()))
        val distance = String.format(java.util.Locale.US, "%.2f km", state.distanceM / 1_000.0)
        return if (state.status == "paused") {
            "Paused • $elapsed • $distance"
        } else {
            "$elapsed • $distance"
        }
    }

    private fun formatDuration(milliseconds: Long): String {
        val totalSeconds = milliseconds / 1_000
        val hours = totalSeconds / 3_600
        val minutes = (totalSeconds % 3_600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format(java.util.Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(java.util.Locale.US, "%02d:%02d", minutes, seconds)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Workout recording",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows duration and distance while a workout is being recorded"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        stopLocationUpdates()
        super.onDestroy()
    }
}
