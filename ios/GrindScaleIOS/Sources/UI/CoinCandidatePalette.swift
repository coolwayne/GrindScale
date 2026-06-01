import SwiftUI
import UIKit

/// 硬幣偵測候選名次與圖上圈圈、列表色塊共用，避免「看不出哪個顏色是第幾名」。
enum CoinCandidatePalette {
    static func uiColor(rank: Int, selected: Bool) -> UIColor {
        let idx = (max(1, rank) - 1) % baseColors.count
        let base = baseColors[idx]
        if selected {
            return base
        }
        return base.withAlphaComponent(0.92)
    }

    static func swiftUIColor(rank: Int, selected: Bool) -> Color {
        Color(uiColor: uiColor(rank: rank, selected: selected))
    }

    /// 名次 1…10 各一色，與圖上候選圈一致。
    private static let baseColors: [UIColor] = [
        UIColor(red: 0.95, green: 0.25, blue: 0.22, alpha: 1.0), // 1 紅
        UIColor(red: 1.0, green: 0.48, blue: 0.0, alpha: 1.0), // 2 橘
        UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0), // 3 紫（避免與黃色最終圈混淆）
        UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0), // 4 綠
        UIColor(red: 0.0, green: 0.78, blue: 0.75, alpha: 1.0), // 5 青綠
        UIColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 1.0), // 6 藍
        UIColor(red: 0.25, green: 0.35, blue: 0.95, alpha: 1.0), // 7 靛
        UIColor(red: 1.0, green: 0.35, blue: 0.65, alpha: 1.0), // 8 粉
        UIColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1.0), // 9 棕
        UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0), // 10 金黃
    ]
}
