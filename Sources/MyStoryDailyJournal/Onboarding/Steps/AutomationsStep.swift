import SwiftUI

/// §7 step 5: offered, but deliberately secondary — "someone who just
/// wants the plain app shouldn't feel like they're missing a step by
/// skipping this." Lands here (M8) rather than earlier, since it needs
/// `IngestSharedContentIntent` to exist first.
struct AutomationsStep: View {
    @State private var expandedTemplate: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Optional automations")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 24)

                Text("These pull content from Notes or Messages into My Story on their own, entirely through your own Shortcuts app. Skip this if you'd rather just write.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                templateCard(.notesDailyPull)
                templateCard(.messageTrigger)
            }
            .padding(.horizontal)
        }
    }

    private func templateCard(_ template: ShortcutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)
            Text(template.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(expandedTemplate == template.name ? "Hide steps" : "Show setup steps") {
                expandedTemplate = expandedTemplate == template.name ? nil : template.name
            }
            .font(.footnote)

            if expandedTemplate == template.name {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(template.manualSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
            }

            Button("Open Shortcuts") {
                template.open()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
