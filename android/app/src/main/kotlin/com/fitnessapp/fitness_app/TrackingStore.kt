package com.fitnessapp.fitness_app

import android.content.Context

data class ActiveTrackingSession(
    val id: String,
    val status: String,
    val createdAt: Long,
    val startedAt: Long?,
    val elapsedMs: Long,
    val activeSegmentStartedAt: Long?,
    val distanceM: Double,
    val pointCount: Int,
    val segmentIndex: Int,
) {
    fun elapsedAt(now: Long): Long =
        elapsedMs +
            if (status == "recording" && activeSegmentStartedAt != null) {
                (now - activeSegmentStartedAt).coerceAtLeast(0)
            } else {
                0
            }

    fun toChannelMap(now: Long = System.currentTimeMillis()): Map<String, Any?> =
        mapOf(
            "status" to status,
            "sessionId" to id,
            "startedAt" to startedAt,
            "elapsedMs" to elapsedAt(now),
            "distanceM" to distanceM,
            "pointCount" to pointCount,
        )
}

/** Small crash-recovery journal for the one active session. */
object TrackingStore {
    private const val PREFS = "tracking_recorder_state"
    private const val ID = "active_id"
    private const val STATUS = "status"
    private const val CREATED_AT = "created_at"
    private const val STARTED_AT = "started_at"
    private const val ELAPSED_MS = "elapsed_ms"
    private const val SEGMENT_STARTED_AT = "segment_started_at"
    private const val DISTANCE_M = "distance_m"
    private const val POINT_COUNT = "point_count"
    private const val SEGMENT_INDEX = "segment_index"
    private const val ASKED_LOCATION = "asked_location"
    private const val ASKED_NOTIFICATIONS = "asked_notifications"

    @Synchronized
    fun read(context: Context): ActiveTrackingSession? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = prefs.getString(ID, null) ?: return null
        val started = prefs.getLong(STARTED_AT, 0L).takeIf { it > 0 }
        val segment = prefs.getLong(SEGMENT_STARTED_AT, 0L).takeIf { it > 0 }
        return ActiveTrackingSession(
            id = id,
            status = prefs.getString(STATUS, "acquiring") ?: "acquiring",
            createdAt = prefs.getLong(CREATED_AT, System.currentTimeMillis()),
            startedAt = started,
            elapsedMs = prefs.getLong(ELAPSED_MS, 0L),
            activeSegmentStartedAt = segment,
            distanceM = java.lang.Double.longBitsToDouble(prefs.getLong(DISTANCE_M, 0L)),
            pointCount = prefs.getInt(POINT_COUNT, 0),
            segmentIndex = prefs.getInt(SEGMENT_INDEX, 0),
        )
    }

    @Synchronized
    fun begin(context: Context, id: String, now: Long): ActiveTrackingSession {
        val state = ActiveTrackingSession(
            id = id,
            status = "acquiring",
            createdAt = now,
            startedAt = null,
            elapsedMs = 0,
            activeSegmentStartedAt = null,
            distanceM = 0.0,
            pointCount = 0,
            segmentIndex = 0,
        )
        write(context, state)
        return state
    }

    @Synchronized
    fun startFromFix(context: Context, now: Long): ActiveTrackingSession? {
        val current = read(context) ?: return null
        if (current.status != "acquiring") return current
        val next = current.copy(
            status = "recording",
            startedAt = now,
            activeSegmentStartedAt = now,
        )
        write(context, next)
        return next
    }

    @Synchronized
    fun pause(context: Context, now: Long): ActiveTrackingSession? {
        val current = read(context) ?: return null
        if (current.status != "recording") return current
        val next = current.copy(
            status = "paused",
            elapsedMs = current.elapsedAt(now),
            activeSegmentStartedAt = null,
        )
        write(context, next)
        return next
    }

    @Synchronized
    fun resume(context: Context, now: Long): ActiveTrackingSession? {
        val current = read(context) ?: return null
        if (current.status != "paused") return current
        // A resumed workout must not draw a straight line across whatever
        // happened while it was paused, so it opens a new segment. Distance is
        // only ever accumulated within a segment, and the index is stamped on
        // each stored point so Step 2's processor keeps the same boundary.
        val next = current.copy(
            status = "recording",
            activeSegmentStartedAt = now,
            segmentIndex = current.segmentIndex + 1,
        )
        write(context, next)
        return next
    }

    @Synchronized
    fun updateMetrics(
        context: Context,
        distanceM: Double,
        pointCount: Int,
    ): ActiveTrackingSession? {
        val current = read(context) ?: return null
        val next = current.copy(distanceM = distanceM, pointCount = pointCount)
        write(context, next)
        return next
    }

    @Synchronized
    fun finish(context: Context, now: Long): ActiveTrackingSession? {
        val current = read(context) ?: return null
        val next = current.copy(
            elapsedMs = current.elapsedAt(now),
            activeSegmentStartedAt = null,
        )
        write(context, next)
        return next
    }

    @Synchronized
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(ID)
            .remove(STATUS)
            .remove(CREATED_AT)
            .remove(STARTED_AT)
            .remove(ELAPSED_MS)
            .remove(SEGMENT_STARTED_AT)
            .remove(DISTANCE_M)
            .remove(POINT_COUNT)
            .remove(SEGMENT_INDEX)
            .commit()
    }

    fun currentMap(context: Context): Map<String, Any?> =
        read(context)?.toChannelMap() ?: mapOf("status" to "idle")

    fun hasAskedLocation(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(ASKED_LOCATION, false)

    fun hasAskedNotifications(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(ASKED_NOTIFICATIONS, false)

    fun markPermissionRequests(
        context: Context,
        location: Boolean,
        notifications: Boolean,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            if (location) putBoolean(ASKED_LOCATION, true)
            if (notifications) putBoolean(ASKED_NOTIFICATIONS, true)
        }.commit()
    }

    private fun write(context: Context, state: ActiveTrackingSession) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(ID, state.id)
            .putString(STATUS, state.status)
            .putLong(CREATED_AT, state.createdAt)
            .putLong(STARTED_AT, state.startedAt ?: 0L)
            .putLong(ELAPSED_MS, state.elapsedMs)
            .putLong(SEGMENT_STARTED_AT, state.activeSegmentStartedAt ?: 0L)
            .putLong(DISTANCE_M, java.lang.Double.doubleToRawLongBits(state.distanceM))
            .putInt(POINT_COUNT, state.pointCount)
            .putInt(SEGMENT_INDEX, state.segmentIndex)
            .commit()
    }
}
