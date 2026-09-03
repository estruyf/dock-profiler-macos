import AppKit
import SwiftUI

/// Click, then press the combination you want. Escape cancels.
struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 96)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove the shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return combo?.displayString ?? "Click to record"
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            if keyCode == escapeKeyCode {
                Task { @MainActor in stopRecording() }
                return nil
            }
            if let recorded = KeyCombo(event: event) {
                Task { @MainActor in
                    combo = recorded
                    stopRecording()
                }
                return nil
            }
            // Modifier-less keys are ignored; keep listening.
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private let escapeKeyCode = 53
