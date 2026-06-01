import SwiftUI
import UIKit

struct SplashView: View {
    let onFinish: () -> Void

    @State private var didFinish = false

    /// 靜態開場停留時間（秒）
    private let splashDuration: TimeInterval = 2.5

    var body: some View {
        GeometryReader { geo in
            let maxW = min(geo.size.width * 0.82, 420)
            ZStack {
                Color.white
                    .ignoresSafeArea()

                // 勿用上下 Spacer 夾圖片，否則 VStack 會把圖片高度壓扁。
                VStack(spacing: 22) {
                    splashArtwork(maxWidth: maxW)
                    Text("GrindScale")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(CoffeeTheme.labelBlack)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + splashDuration) {
                finishOnce()
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            finishOnce()
        }
    }

    @ViewBuilder
    private func splashArtwork(maxWidth: CGFloat) -> some View {
        if let ui = Self.loadLaunchSplashUIImage() {
            let w = max(ui.size.width, 1)
            let h = max(ui.size.height, 1)
            let intrinsicRatio = w / h
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(intrinsicRatio, contentMode: .fit)
                .frame(maxWidth: maxWidth)
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.12))
                .frame(width: maxWidth, height: maxWidth * 0.55)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// `Image(_:)` 只認 Asset Catalog；bundle 內的 PNG 須用 UIImage 或檔案 URL 載入。
    private static func loadLaunchSplashUIImage() -> UIImage? {
        if let img = UIImage(named: "LaunchSplash") {
            return img
        }
        guard let url = Bundle.main.url(forResource: "LaunchSplash", withExtension: "png") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}
