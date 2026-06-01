package com.grindscale.android.services

import com.grindscale.android.domain.AnalysisStats

object RecommendationService {
    fun text(stats: AnalysisStats, profileName: String): String {
        if (stats.particleCount < 30) {
            return "顆粒數量偏少，建議增加樣本量後再分析。"
        }
        if (stats.bimodal) {
            return "分佈呈現雙峰，可能有研磨不一致情況，建議檢查刀盤或重新校正。"
        }
        if (stats.fineRatio > 0.30 && stats.cv > 0.40) {
            return "細粉比例偏高。若使用 $profileName，建議調粗 1 格並降低攪拌。"
        }
        if (stats.coarseRatio > 0.30) {
            return "粗粉比例偏高，建議調細 1 格以提升萃取。"
        }
        if (stats.uniformityScore >= 80) {
            return "均勻度良好，可維持目前設定。"
        }
        return "分佈略寬，建議微調刻度後再次測試。"
    }
}
