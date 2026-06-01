import SwiftUI
import UIKit

/// 溫暖咖啡色系：琥珀、石色、橙調。
enum CoffeeTheme {
    static let background = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let card = Color(red: 1.0, green: 0.98, blue: 0.95)
    static let cardStroke = Color(red: 0.88, green: 0.80, blue: 0.72)
    static let amber = Color(red: 0.72, green: 0.48, blue: 0.28)
    static let deepBrown = Color(red: 0.35, green: 0.22, blue: 0.12)
    static let accent = Color(red: 0.90, green: 0.52, blue: 0.22)
    static let muted = Color(red: 0.45, green: 0.38, blue: 0.34)
    /// 分析數值、標題用純黑，避免深色模式變成白字。
    static let labelBlack = Color.black
}

/// 導覽列標題與按鈕區使用黑字（與淺色背景一致）。
struct CoffeeNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(
                    red: 0.97,
                    green: 0.94,
                    blue: 0.90,
                    alpha: 1
                )
                appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
                appearance.shadowColor = .clear
                let nav = UINavigationBar.appearance()
                nav.standardAppearance = appearance
                nav.compactAppearance = appearance
                nav.scrollEdgeAppearance = appearance
                nav.tintColor = .black
            }
    }
}

extension View {
    func coffeeNavigationBar() -> some View {
        modifier(CoffeeNavigationBarStyle())
    }
}

/// 取代 `borderedProminent`（系統會在有色底上用白字），改為**黑字**＋填色背景。
struct CoffeeProminentButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(CoffeeTheme.labelBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(fill.opacity(configuration.isPressed ? 0.88 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}
