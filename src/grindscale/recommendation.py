from __future__ import annotations

from grindscale.models import AnalysisStats


def build_recommendation(stats: AnalysisStats, brew_profile_name: str) -> str:
    if stats.particle_count < 30:
        return "顆粒數量偏少，建議增加樣本量再分析，結果會更穩定。"

    if stats.bimodal:
        return "分佈呈現雙峰，可能有切削不一致。建議檢查磨豆機刀盤狀態或校正。"

    if stats.fine_ratio > 0.30 and stats.cv > 0.40:
        return f"細粉比例偏高且分散度大。若用 {brew_profile_name}，建議調粗 1 格並降低攪拌。"

    if stats.coarse_ratio > 0.30:
        return f"粗粉比例偏高，萃取可能偏淡。若用 {brew_profile_name}，可嘗試調細 1 格。"

    if stats.uniformity_score >= 80:
        return "研磨均勻度良好，可維持目前設定。"

    return "分佈略寬，建議微調刻度後再測一次，觀察細粉與粗粉比例變化。"
