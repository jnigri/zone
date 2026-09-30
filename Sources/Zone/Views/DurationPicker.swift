import SwiftUI

struct DurationPicker: View {
    @Environment(AppState.self) private var state

    private var isCustom: Bool { !AppState.presets.contains(state.timer.duration) }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppState.presets, id: \.self) { preset in
                Chip(title: preset.durationLabel, selected: state.timer.duration == preset) {
                    state.setDuration(preset)
                }
            }
            CustomChip(
                title: isCustom ? state.timer.duration.durationLabel : "Custom",
                selected: isCustom,
                current: state.timer.duration
            ) { state.setDuration($0) }
        }
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(selected: selected) { Text(title) }
        }
        .buttonStyle(.plain)
    }
}

private struct ChipLabel<Content: View>: View {
    let selected: Bool
    var invalid = false
    @ViewBuilder let content: Content

    @Environment(\.palette) private var palette

    var body: some View {
        content
            .font(.system(.callout, design: .rounded, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 48)
            .background(selected ? palette.raised : palette.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .foregroundStyle(selected ? palette.text : palette.muted)
            .contentShape(Capsule())
    }

    private var border: Color {
        if invalid { return palette.wrong }
        return selected ? palette.accent.opacity(0.6) : .clear
    }
}

/// Custom chip that turns into a text field in place. Accepts loose input
/// like "12m", "1h 40m", "120s" (see DurationParser).
private struct CustomChip: View {
    let title: String
    let selected: Bool
    let current: TimeInterval
    let onSet: (TimeInterval) -> Void

    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: TimeInterval? { DurationParser.parse(text) }
    private var invalid: Bool { !text.isEmpty && parsed == nil }

    var body: some View {
        if editing {
            ChipLabel(selected: true, invalid: invalid) {
                TextField("30m", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
            }
            .onAppear { focused = true }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
        } else {
            Chip(title: title, selected: selected) {
                text = current.durationLabel
                editing = true
            }
        }
    }

    private func commit() {
        guard editing else { return }
        if let parsed {
            onSet(parsed)
            editing = false
        } else if text.isEmpty || !focused {
            // Empty or abandoned invalid input: fall back to the chip.
            editing = false
        }
    }

    private func cancel() {
        editing = false
    }
}
