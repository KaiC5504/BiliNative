import SwiftUI

/// 倍速 (06): a plain column of values on the dimmed video in landscape, a grid in the portrait sheet.
struct SpeedPanel: View {
    let model: VideoPageModel
    let close: () -> Void
    @Environment(\.panelLandscape) private var landscape

    struct Choice: Identifiable {
        let rate: Float
        let label: String
        var id: Float { rate }
    }

    static let choices = [
        Choice(rate: 3, label: "3.0X"), Choice(rate: 2, label: "2.0X"), Choice(rate: 1.5, label: "1.5X"),
        Choice(rate: 1.25, label: "1.25X"), Choice(rate: 1, label: "1.0X"), Choice(rate: 0.75, label: "0.75X"),
        Choice(rate: 0.5, label: "0.5X"),
    ]

    var body: some View {
        if landscape {
            VStack(spacing: 0) {
                ForEach(Self.choices) { choice in
                    button(choice)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "倍速")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PanelMetrics.gap), count: 4), spacing: PanelMetrics.gap) {
                    ForEach(Self.choices) { choice in
                        button(choice)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Theme.panelCard, in: RoundedRectangle(cornerRadius: PanelMetrics.rowRadius))
                    }
                }
            }
        }
    }

    private func button(_ choice: Choice) -> some View {
        let selected = model.rate == choice.rate
        return Button {
            model.rate = choice.rate
            close()
        } label: {
            Text(choice.label)
                .font(.system(size: 14))
                .foregroundStyle(selected ? Theme.pink : Theme.panelText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
