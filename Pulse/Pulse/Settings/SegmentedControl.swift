import SwiftUI

/// The design's neutral segmented control (spec §19.4): selection is a raised pill in the current
/// appearance's neutral — a white pill with a soft shadow in Light, a translucent white lift in
/// Dark — never the accent. The stock `.segmented` picker on macOS 26 fills its selection with
/// the accent colour, which is exactly what the redesign removes ("green means *on*; selections
/// are neutral"), so this small control owns its four states itself.
struct SegmentedControl<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    let selection: Value
    let select: (Value) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option.label, value: option.value)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
    }

    private func segment(_ label: String, value: Value) -> some View {
        let selected = value == selection
        return Button { select(value) } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .monospacedDigit()
                // Never truncate a segment: the row's `Spacer` is what gives, not the labels.
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 3.5)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 5.5)
                            .fill(scheme == .dark ? Color.white.opacity(0.19) : Color.white)
                            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.12), radius: 1, y: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 5.5))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
