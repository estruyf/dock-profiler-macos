import AppKit
import SwiftUI

/// First run: one sentence, one button. No tour, no carousel.
struct WelcomeView: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var settings = AppSettings.shared
    let onFinish: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            appIcon
                .padding(.top, 46)
                .padding(.bottom, 24)

            Text("Dock Profiler saves your Dock")
                .font(.system(size: 27, weight: .bold))

            Text("A profile is a snapshot of your pinned apps. Switch to it from the menu bar and your Dock becomes that again — everything else on your Mac is left alone.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 470)
                .padding(.top, 10)

            steps
                .padding(.horizontal, 34)
                .padding(.top, 26)

            HStack(spacing: 14) {
                Button("Skip for now") { onFinish(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Save my current Dock") { saveCurrentDock() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)

            Text("Dock Profiler asks for no permissions at all — it reads and writes your Dock, and nothing else.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 18)
                .padding(.bottom, 26)
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.60, blue: 0.93), Color(red: 0.29, green: 0.47, blue: 0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 104, height: 104)
            .overlay(alignment: .bottom) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(index == 0 ? 1 : 0.6))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.22))
                )
                .padding(.bottom, 18)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var steps: some View {
        VStack(spacing: 0) {
            step(1, highlighted: true,
                 title: "Save the Dock you have now",
                 detail: "It becomes your first profile. Nothing about your Dock changes.")
            Divider().padding(.leading, 54)
            step(2, highlighted: false,
                 title: "Rearrange your Dock, save it again",
                 detail: "Two profiles is when Dock Profiler starts being useful.")
            Divider().padding(.leading, 54)
            shortcutStep
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func step(_ number: Int, highlighted: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            badge(number, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var shortcutStep: some View {
        HStack(alignment: .top, spacing: 14) {
            badge(3, highlighted: false)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Press").font(.system(size: 15, weight: .medium))
                    KeyCap(settings.switcherShortcut?.displayString ?? "⌥⌘D")
                    Text("to switch").font(.system(size: 15, weight: .medium))
                }
                Text("Or pick from the menu bar icon. Both do the same thing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func badge(_ number: Int, highlighted: Bool) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(highlighted ? .white : .secondary)
            .frame(width: 26, height: 26)
            .background(
                Circle().fill(highlighted ? Color.accentColor : Color.primary.opacity(0.08))
            )
    }

    private func saveCurrentDock() {
        let profile = store.createProfile(named: "My Dock")
        onFinish(profile.id)
    }
}
