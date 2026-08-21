import SwiftUI

struct SectionHeaderView: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        // Read as one header instead of "Today" then a bare number, and marked
        // as a header so VoiceOver's rotor can jump between the date groups.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "a11y.section", defaultValue: "\(title), \(count) screenshots"))
        .accessibilityAddTraits(.isHeader)
    }
}
