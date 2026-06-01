package com.grindscale.android.domain

import java.util.UUID

enum class ParticleClass { fine, target, coarse }

data class BrewProfile(
    val id: String,
    val name: String,
    val fineThresholdUM: Double,
    val coarseThresholdUM: Double,
    val relativeFineRatio: Double,
    val relativeCoarseRatio: Double,
    val idealRangeDescription: String
)

object Profiles {
    val all: List<BrewProfile> = listOf(
        BrewProfile("espresso", "義式咖啡", 200.0, 600.0, 0.68, 1.38, "約 200–600 µm"),
        BrewProfile("moka", "摩卡壺", 220.0, 560.0, 0.72, 1.40, "約 220–560 µm"),
        BrewProfile("v60", "手沖咖啡", 400.0, 900.0, 0.70, 1.35, "約 400–900 µm"),
        BrewProfile("french", "法式壓濾壺", 600.0, 1400.0, 0.65, 1.45, "約 600–1400 µm")
    )
    val skipDefault: BrewProfile get() = all.firstOrNull { it.id == "v60" } ?: all.first()
}

enum class RoastLevel(val label: String) {
    light("淺焙"),
    mediumLight("中淺焙"),
    medium("中焙"),
    mediumDark("中深焙"),
    dark("深焙")
}

data class CoinReference(val id: String, val name: String, val diameterMM: Double?)

object CoinReferences {
    val all: List<CoinReference> = listOf(
        CoinReference("none", "不使用（相對模式）", null),
        CoinReference("twd1", "TWD 1 元", 20.0),
        CoinReference("twd5", "TWD 5 元", 22.0),
        CoinReference("twd10", "TWD 10", 26.5),
        CoinReference("twd50", "TWD 50 元", 28.0)
    )
}

enum class AnalysisMode { relative, calibrated }

data class Particle(
    val id: UUID = UUID.randomUUID(),
    val centerX: Double,
    val centerY: Double,
    val radiusPx: Float,
    val diameterPx: Double,
    val diameterUM: Double?,
    val kind: ParticleClass,
    val contour: List<Pair<Float, Float>>
)

data class CoinMarker(val centerX: Double, val centerY: Double, val radiusPx: Float)

data class CoinCandidateDebug(
    val rank: Int,
    val area: Double,
    val circularity: Double,
    val support: Double,
    val score: Double,
    val selected: Boolean
)

data class CoinCandidateOverlay(
    val rank: Int,
    val centerX: Double,
    val centerY: Double,
    val radiusPx: Float,
    val selected: Boolean
)

data class AnalysisStats(
    val particleCount: Int,
    val mean: Double,
    val std: Double,
    val cv: Double,
    val d10: Double,
    val d50: Double,
    val d90: Double,
    val fineRatio: Double,
    val targetRatio: Double,
    val coarseRatio: Double,
    val bimodal: Boolean,
    val uniformityScore: Int,
    val mode: AnalysisMode,
    val unitLabel: String
)

data class AnalysisResult(
    val stats: AnalysisStats,
    val particles: List<Particle>,
    val diameters: List<Double>,
    val calibrationText: String,
    val analyzedWidth: Int,
    val analyzedHeight: Int,
    val coinMarker: CoinMarker?,
    val coinCandidates: List<CoinCandidateDebug>,
    val coinCandidateOverlays: List<CoinCandidateOverlay>
)

data class AnalysisHistoryRecord(
    val id: UUID,
    val timestampMillis: Long,
    val profileName: String,
    val mode: AnalysisMode,
    val score: Int,
    val particleCount: Int,
    val cv: Double
)

data class HistogramBin(
    val id: String = UUID.randomUUID().toString(),
    val start: Double,
    val end: Double,
    val count: Int
)
