import SwiftUI

enum AppPhase {
    case splash
    case home
    case analysis
}

struct HomeView: View {
    @ObservedObject var vm: ContentViewModel
    @Binding var phase: AppPhase

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("選擇沖煮方式")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CoffeeTheme.labelBlack)
                    Text("依器具對應理想粒徑區間；可展開填寫豆種與設備。")
                        .font(.subheadline)
                        .foregroundStyle(Color.black.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Profiles.all) { profile in
                        BrewMethodCard(
                            profile: profile,
                            isSelected: vm.selectedProfile.id == profile.id
                        ) {
                            vm.selectedProfile = profile
                        }
                    }
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("豆種 / 產區") {
                            TextField("選填，例如：衣索比亞 耶加雪菲", text: $vm.beanDescription)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("烘焙程度") {
                            Picker("", selection: $vm.roastLevel) {
                                ForEach(RoastLevel.allCases) { level in
                                    Text(level.label).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        LabeledContent("磨豆機") {
                            TextField("選填，例如：Baratza Encore", text: $vm.grinderDescription)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("更多選項（選填）", systemImage: "leaf.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CoffeeTheme.labelBlack)
                }
                .tint(CoffeeTheme.labelBlack)

                VStack(spacing: 12) {
                    Button {
                        phase = .analysis
                    } label: {
                        Text("進入分析")
                            .font(.headline)
                    }
                    .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.amber))

                    Button {
                        vm.selectedProfile = Profiles.skipDefault
                        phase = .analysis
                    } label: {
                        Text("SKIP")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CoffeeTheme.labelBlack)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Text("SKIP 將以「手沖咖啡」為預設沖煮方式。")
                        .font(.caption2)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(CoffeeTheme.background)
        .navigationTitle("GrindScale")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CoffeeTheme.background, for: .navigationBar)
        .coffeeNavigationBar()
    }
}

private struct BrewMethodCard: View {
    let profile: BrewProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(CoffeeTheme.labelBlack)
                    .multilineTextAlignment(.leading)
                Text("理想粒徑")
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.55))
                Text(profile.idealRangeDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoffeeTheme.labelBlack)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(CoffeeTheme.card)
                    .shadow(color: CoffeeTheme.deepBrown.opacity(0.08), radius: isSelected ? 8 : 4, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? CoffeeTheme.accent : CoffeeTheme.cardStroke, lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
