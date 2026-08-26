import SwiftUI
import UIKit

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

                noSetupNeededCard

                templateCard(.notesDailyPull)
                templateCard(.messageTrigger)
            }
            .padding(.horizontal)
        }
    }

    /// The most common worry from someone unfamiliar with Shortcuts is that
    /// they *have* to figure all this out — they don't. Say so up front.
    private var noSetupNeededCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The basics already work — no setup", systemImage: "checkmark.circle")
                .font(.headline)
            Text("You can already say \"Hey Siri, log my day in My Story,\" and \"Add to My Story\" already shows up in the share sheet and the Shortcuts app. The automations below are extras for later — set them up any time, or never.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func templateCard(_ template: ShortcutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)
            Text(template.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(expandedTemplate == template.name ? "Hide steps" : "Show me every tap") {
                expandedTemplate = expandedTemplate == template.name ? nil : template.name
            }
            .font(.footnote)

            if expandedTemplate == template.name {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(template.manualSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
            }

            // Opening Shortcuts closes this app and takes the steps with it,
            // so they go to the clipboard first — pasteable into any text
            // field over there if memory runs out mid-setup.
            Button("Copy steps & open Shortcuts") {
                UIPasteboard.general.string = template.stepsText
                template.open()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)

            Text("The steps are copied automatically — if you lose your place in Shortcuts, paste them anywhere to see them again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
