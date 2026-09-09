package com.fitnessapp.fitness_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

data class StoredTrackingPoint(
    val latitude: Double,
    val longitude: Double,
)

/**
 * Append-only route storage owned by the recorder, not the UI process.
 *
 * A point is committed before the next GPS fix is handled. If Android kills
 * Flutter or the whole application process, at most the fix currently being
 * delivered is at risk; the route never lives only in Dart memory.
 */
class TrackingDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "tracking_recorder.db"
        private const val DATABASE_VERSION = 2

        @Volatile
        private var instance: TrackingDatabase? = null

        fun get(context: Context): TrackingDatabase =
            instance ?: synchronized(this) {
                instance ?: TrackingDatabase(context).also { instance = it }
            }
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE tracking_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                started_at INTEGER,
                ended_at INTEGER,
                elapsed_ms INTEGER NOT NULL DEFAULT 0,
                distance_m REAL NOT NULL DEFAULT 0,
                point_count INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE tracking_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                captured_at INTEGER NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude_m REAL,
                accuracy_m REAL NOT NULL,
                speed_mps REAL NOT NULL,
                bearing_degrees REAL NOT NULL,
                accepted_live INTEGER NOT NULL,
                is_mock INTEGER NOT NULL,
                segment INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(session_id) REFERENCES tracking_sessions(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        createPointIndex(db)
    }

    private fun createPointIndex(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS tracking_points_session_time " +
                "ON tracking_points(session_id, segment, captured_at, id)",
        )
    }

    /**
     * v1 → v2 rebuilds `tracking_points` to add the segment index and to let
     * `altitude_m` be null.
     *
     * SQLite cannot drop a NOT NULL constraint in place, so the table is
     * recreated and copied. v1 wrote 0.0 whenever the fix carried no altitude,
     * which is why the copy maps 0 back to null — keeping it would tell the
     * elevation profile the runner dropped to sea level and back.
     */
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion >= newVersion) return
        db.execSQL("ALTER TABLE tracking_points RENAME TO tracking_points_v1")
        db.execSQL(
            """
            CREATE TABLE tracking_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                captured_at INTEGER NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude_m REAL,
                accuracy_m REAL NOT NULL,
                speed_mps REAL NOT NULL,
                bearing_degrees REAL NOT NULL,
                accepted_live INTEGER NOT NULL,
                is_mock INTEGER NOT NULL,
                segment INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(session_id) REFERENCES tracking_sessions(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            INSERT INTO tracking_points (
                id, session_id, captured_at, latitude, longitude, altitude_m,
                accuracy_m, speed_mps, bearing_degrees, accepted_live, is_mock,
                segment
            )
            SELECT
                id, session_id, captured_at, latitude, longitude,
                NULLIF(altitude_m, 0),
                accuracy_m, speed_mps, bearing_degrees, accepted_live, is_mock, 0
            FROM tracking_points_v1
            """.trimIndent(),
        )
        db.execSQL("DROP TABLE tracking_points_v1")
        createPointIndex(db)
    }

    @Synchronized
    fun createSession(id: String, createdAt: Long) {
        writableDatabase.insertOrThrow(
            "tracking_sessions",
            null,
            ContentValues().apply {
                put("id", id)
                put("status", "acquiring")
                put("created_at", createdAt)
            },
        )
    }

    @Synchronized
    fun updateSession(state: ActiveTrackingSession, endedAt: Long? = null) {
        writableDatabase.update(
            "tracking_sessions",
            ContentValues().apply {
                put("status", state.status)
                if (state.startedAt == null) putNull("started_at") else put("started_at", state.startedAt)
                if (endedAt == null) putNull("ended_at") else put("ended_at", endedAt)
                put("elapsed_ms", state.elapsedMs)
                put("distance_m", state.distanceM)
                put("point_count", state.pointCount)
            },
            "id = ?",
            arrayOf(state.id),
        )
    }

    @Synchronized
    fun insertPoint(
        sessionId: String,
        capturedAt: Long,
        latitude: Double,
        longitude: Double,
        altitudeM: Double?,
        accuracyM: Float,
        speedMps: Float,
        bearingDegrees: Float,
        acceptedForLiveDistance: Boolean,
        isMock: Boolean,
        segment: Int,
    ) {
        writableDatabase.insertOrThrow(
            "tracking_points",
            null,
            ContentValues().apply {
                put("session_id", sessionId)
                put("captured_at", capturedAt)
                put("latitude", latitude)
                put("longitude", longitude)
                if (altitudeM == null) putNull("altitude_m") else put("altitude_m", altitudeM)
                put("accuracy_m", accuracyM)
                put("speed_mps", speedMps)
                put("bearing_degrees", bearingDegrees)
                put("accepted_live", if (acceptedForLiveDistance) 1 else 0)
                put("is_mock", if (isMock) 1 else 0)
                put("segment", segment)
            },
        )
    }

    @Synchronized
    fun lastAcceptedPoint(sessionId: String, segment: Int): StoredTrackingPoint? {
        readableDatabase.query(
            "tracking_points",
            arrayOf("latitude", "longitude"),
            "session_id = ? AND segment = ? AND accepted_live = 1",
            arrayOf(sessionId, segment.toString()),
            null,
            null,
            "captured_at DESC, id DESC",
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return StoredTrackingPoint(
                latitude = cursor.getDouble(0),
                longitude = cursor.getDouble(1),
            )
        }
    }

    @Synchronized
    fun completeSession(state: ActiveTrackingSession, endedAt: Long) {
        updateSession(state.copy(status = "completed"), endedAt)
    }

    @Synchronized
    fun discardSession(sessionId: String) {
        writableDatabase.delete("tracking_sessions", "id = ?", arrayOf(sessionId))
    }

    @Synchronized
    fun listPoints(sessionId: String): List<Map<String, Any?>> {
        val points = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            "tracking_points",
            arrayOf(
                "captured_at",
                "latitude",
                "longitude",
                "altitude_m",
                "accuracy_m",
                "speed_mps",
                "bearing_degrees",
                "accepted_live",
                "is_mock",
                "segment",
            ),
            "session_id = ?",
            arrayOf(sessionId),
            null,
            null,
            "segment ASC, captured_at ASC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                points += mapOf(
                    "capturedAt" to cursor.getLong(0),
                    "latitude" to cursor.getDouble(1),
                    "longitude" to cursor.getDouble(2),
                    "altitudeM" to if (cursor.isNull(3)) null else cursor.getDouble(3),
                    "accuracyM" to cursor.getDouble(4),
                    "speedMps" to cursor.getDouble(5),
                    "bearingDegrees" to cursor.getDouble(6),
                    "acceptedForLiveDistance" to (cursor.getInt(7) == 1),
                    "isMock" to (cursor.getInt(8) == 1),
                    "segmentIndex" to cursor.getInt(9),
                )
            }
        }
        return points
    }
}
