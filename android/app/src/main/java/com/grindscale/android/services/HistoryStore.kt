package com.grindscale.android.services

import android.content.Context
import com.grindscale.android.domain.AnalysisHistoryRecord
import com.grindscale.android.domain.AnalysisMode
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class HistoryStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val key = "grindscale.analysis.history"
    private val maxRecords = 30

    fun load(): List<AnalysisHistoryRecord> {
        val jsonStr = prefs.getString(key, null) ?: return emptyList()
        return try {
            val arr = JSONArray(jsonStr)
            buildList(arr.length()) {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(
                        AnalysisHistoryRecord(
                            id = UUID.fromString(o.getString("id")),
                            timestampMillis = o.getLong("timestampMillis"),
                            profileName = o.getString("profileName"),
                            mode = if (o.getString("mode") == "calibrated") AnalysisMode.calibrated else AnalysisMode.relative,
                            score = o.getInt("score"),
                            particleCount = o.getInt("particleCount"),
                            cv = o.getDouble("cv")
                        )
                    )
                }
            }.sortedByDescending { it.timestampMillis }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(record: AnalysisHistoryRecord) {
        val records = load().toMutableList()
        records.add(0, record)
        if (records.size > maxRecords) {
            records.subList(maxRecords, records.size).clear()
        }
        val arr = JSONArray()
        for (r in records) {
            arr.put(
                JSONObject().apply {
                    put("id", r.id.toString())
                    put("timestampMillis", r.timestampMillis)
                    put("profileName", r.profileName)
                    put("mode", if (r.mode == AnalysisMode.calibrated) "calibrated" else "relative")
                    put("score", r.score)
                    put("particleCount", r.particleCount)
                    put("cv", r.cv)
                }
            )
        }
        prefs.edit().putString(key, arr.toString()).apply()
    }

    companion object {
        private const val PREFS = "grindscale_prefs"
    }
}
