import Foundation
import CoreGraphics

enum ParticleClass: String, CaseIterable {
    case fine
    case target
    case coarse
}

struct BrewProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let fineThresholdUM: Double
    let coarseThresholdUM: Double
    let relativeFineRatio: Double
    let relativeCoarseRatio: Double
    /// 首頁卡片顯示的理想粒徑區間（參考用）
    let idealRangeDescription: String
}

enum Profiles {
    static let all: [BrewProfile] = [
        BrewProfile(
            id: "espresso",
            name: "義式咖啡",
            fineThresholdUM: 200,
            coarseThresholdUM: 600,
            relativeFineRatio: 0.68,
            relativeCoarseRatio: 1.38,
            idealRangeDescription: "約 200–600 µm"
        ),
        BrewProfile(
            id: "moka",
            name: "摩卡壺",
            fineThresholdUM: 220,
            coarseThresholdUM: 560,
            relativeFineRatio: 0.72,
            relativeCoarseRatio: 1.40,
            idealRangeDescription: "約 220–560 µm"
        ),
        BrewProfile(
            id: "v60",
            name: "手沖咖啡",
            fineThresholdUM: 400,
            coarseThresholdUM: 900,
            relativeFineRatio: 0.70,
            relativeCoarseRatio: 1.35,
            idealRangeDescription: "約 400–900 µm"
        ),
        BrewProfile(
            id: "french",
            name: "法式壓濾壺",
            fineThresholdUM: 600,
            coarseThresholdUM: 1400,
            relativeFineRatio: 0.65,
            relativeCoarseRatio: 1.45,
            idealRangeDescription: "約 600–1400 µm"
        )
    ]

    /// SKIP 進入分析時的預設沖煮（手沖）
    static var skipDefault: BrewProfile {
        all.first(where: { $0.id == "v60" }) ?? all[0]
    }
}

enum RoastLevel: String, CaseIterable, Identifiable {
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "淺焙"
        case .mediumLight: return "中淺焙"
        case .medium: return "中焙"
        case .mediumDark: return "中深焙"
        case .dark: return "深焙"
        }
    }
}

struct CoinReference: Identifiable, Hashable {
    let id: String
    let name: String
    let diameterMM: Double?
}

enum CoinReferences {
    static let all: [CoinReference] = [
        CoinReference(id: "none", name: "不使用（相對模式）", diameterMM: nil),
        CoinReference(id: "twd1", name: "TWD 1 元", diameterMM: 20.0),
        CoinReference(id: "twd5", name: "TWD 5 元", diameterMM: 22.0),
        CoinReference(id: "twd10", name: "TWD 10", diameterMM: 26.5),
        CoinReference(id: "twd50", name: "TWD 50 元", diameterMM: 28.0)
    ]
}

enum AnalysisMode: String, Codable {
    case relative
    case calibrated
}

struct Particle: Identifiable {
    let id = UUID()
    let center: CGPoint
    let radius: CGFloat
    let diameterPx: Double
    let diameterUM: Double?
    let kind: ParticleClass
    let contour: [CGPoint]
}

struct CoinMarker {
    let center: CGPoint
    let radius: CGFloat
}

struct CoinCandidateDebug: Identifiable {
    let id = UUID()
    let rank: Int
    let area: Double
    let circularity: Double
    let support: Double
    let score: Double
    let selected: Bool
}

struct CoinCandidateOverlay {
    let rank: Int
    let center: CGPoint
    let radius: CGFloat
    let selected: Bool
}

struct AnalysisStats {
    let particleCount: Int
    let mean: Double
    let std: Double
    let cv: Double
    let d10: Double
    let d50: Double
    let d90: Double
    let fineRatio: Double
    let targetRatio: Double
    let coarseRatio: Double
    let bimodal: Bool
    let uniformityScore: Int
    let mode: AnalysisMode
    let unitLabel: String
}

struct AnalysisResult {
    let stats: AnalysisStats
    let particles: [Particle]
    let diameters: [Double]
    let calibrationText: String
    let analyzedWidth: Int
    let analyzedHeight: Int
    let coinMarker: CoinMarker?
    let coinCandidates: [CoinCandidateDebug]
    let coinCandidateOverlays: [CoinCandidateOverlay]
}

struct AnalysisHistoryRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let profileName: String
    let mode: AnalysisMode
    let score: Int
    let particleCount: Int
    let cv: Double
}

struct HistogramBin: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let count: Int
}
