import SwiftUI
import PluginDeckCore

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

struct PluginIcon: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

struct TrustBadge: View {
    let level: PluginManifest.TrustLevel

    var body: some View {
        Label(level.displayName, systemImage: level == .official ? "checkmark.seal.fill" : "person.2")
            .font(.caption)
            .foregroundStyle(level == .official ? Color.green : Color.secondary)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
