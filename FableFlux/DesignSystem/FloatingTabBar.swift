import SwiftUI

// MARK: - Tab-definitie

struct FloatingTab: Identifiable {
    let id: Int
    let icon: String
    let title: String
}

let appTabs: [FloatingTab] = [
    FloatingTab(id: 0, icon: "newspaper", title: "Vandaag"),
    FloatingTab(id: 1, icon: "list.bullet.rectangle", title: "Artikelen"),
    FloatingTab(id: 2, icon: "bookmark", title: "Bewaard"),
]

// MARK: - Zwevende tab bar

/// Luchtige, zwevende tab bar conform de PDF ("Floating Tab Bar").
/// Geselecteerde tab krijgt een gevulde pill in de accentkleur + haptische feedback.
struct FloatingTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(appTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tabButton(_ tab: FloatingTab) -> some View {
        let isSelected = selection == tab.id
        Button {
            guard selection != tab.id else { return }
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                selection = tab.id
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Container-modifier

/// Verbergt de native tab bar en plaatst de zwevende bar als bottom safe-area inset,
/// zodat scroll-content netjes boven de bar eindigt.
struct FloatingTabBarContainer: ViewModifier {
    @Binding var selection: Int

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selection: $selection)
            }
    }
}

extension View {
    func floatingTabBar(selection: Binding<Int>) -> some View {
        modifier(FloatingTabBarContainer(selection: selection))
    }
}
