import SwiftUI

struct AppRootView: View {
    @StateObject private var vm = ContentViewModel()
    @State private var phase: AppPhase = .splash

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .home
                    }
                }
                .transition(.opacity)

            case .home:
                NavigationStack {
                    HomeView(vm: vm, phase: $phase)
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

            case .analysis:
                NavigationStack {
                    AnalysisView(vm: vm) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            phase = .home
                        }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            }
        }
        .preferredColorScheme(.light)
    }
}
