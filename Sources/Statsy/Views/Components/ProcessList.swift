import StatsyKit
import SwiftUI

/// A ranked process list with a magnitude bar behind each row.
struct ProcessList: View {
    let processes: [ProcessSample]
    let accent: Color
    /// Renders the value column for one process.
    let value: (ProcessSample) -> String
    /// The magnitude used to size the row's bar, in the same unit as `value`.
    let magnitude: (ProcessSample) -> Double

    var body: some View {
        // Bound once: read from the row builder this rescanned per row.
        let peak = max(processes.map(magnitude).max() ?? 1, .leastNonzeroMagnitude)
        VStack(spacing: 0) {
            ForEach(processes) { process in
                row(process, peak: peak)
            }
            // Hold the pane's height steady while the first `top` block arrives.
            if processes.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ process: ProcessSample, peak: Double) -> some View {
        HStack(spacing: 7) {
            Text(process.name)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value(process))
                .font(Theme.numeral(16))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(accent.opacity(0.15))
                    .frame(width: geometry.size.width * (magnitude(process) / peak).clamped01)
            }
        }
    }
}
