import AppKit
import SwiftUI

/// The Spotlight-style profile switcher.
///
/// Readability first: the blur is tinted well towards opaque so text keeps its
/// contrast whatever is on the desktop behind it.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @EnvironmentObject private var store: ProfileStore
    @FocusState private var isFieldFocused: Bool
    let onActivate: (DockProfile) -> Void

    private let width: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            searchField
            separator
            if model.results.isEmpty {
                emptyState
            } else {
                resultsList
            }
            separator
            footer
        }
        .frame(width: width)
        .background(SwitcherBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15))
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    Text("Search profiles…")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                }
                TextField("", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($isFieldFocused)
            }
            if store.isApplying {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .task { isFieldFocused = true }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profiles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, profile in
                        SwitcherRow(
                            profile: profile,
                            index: index,
                            isSelected: index == model.selectedIndex,
                            isActive: profile.id == store.activeProfileID
                        )
                        .id(profile.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(profile) }
                        .onHover { hovering in
                            if hovering { model.select(index) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(height: listHeight)
            .onChange(of: model.selectedIndex) { _, _ in
                if let profile = model.selectedProfile {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(profile.id) }
                }
            }
        }
    }

    /// Explicit height: a ScrollView brings none of its own, and the panel sizes
    /// itself to this view.
    private var listHeight: CGFloat {
        let rows = CGFloat(model.results.count)
        return min(rows * 46 + 34, 400)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text(store.profiles.isEmpty ? "No profiles yet" : "No profile matches “\(model.query)”")
                .font(.system(size: 14, weight: .medium))
            Text(store.profiles.isEmpty
                 ? "Save your current Dock from the menu bar to get started."
                 : "Try a different search.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↵", "Activate")
            hint("↑↓", "Navigate")
            hint("⌘1–9", "Jump")
            Spacer()
            hint("esc", "Close")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.primary.opacity(0.05))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            KeyCap(key)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Small keyboard-key chip, readable on both light and dark backgrounds.
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
    }
}

private struct SwitcherRow: View {
    let profile: DockProfile
    let index: Int
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(profile.color.color.opacity(0.25))
                    .frame(width: 28, height: 28)
                Image(systemName: profile.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(profile.color.color)
            }

            Text(profile.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Text(profile.itemSummary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if isActive {
                Text("Active")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(profile.color.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(profile.color.color.opacity(0.20)))
            }

            Spacer(minLength: 8)

            if index < 9 {
                KeyCap("⌘\(index + 1)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.13) : .clear)
        )
    }
}

/// Blur, plus a tint heavy enough that the desktop behind never washes the text out.
private struct SwitcherBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color(nsColor: .windowBackgroundColor).opacity(0.80)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
