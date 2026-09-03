import SwiftUI

struct WritingStyleStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var customPromptDrafts: [String] = ["", "", ""]

    var body: some View {
        Form {
            Section("When you write yourself") {
                Picker("Style", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Text("This controls the entry screen when you decide to write. Automatic drafts and facts-only days are set on the next screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if settings.writingStyle != .freeform {
                Section("Prompts") {
                    Picker("Question set", selection: $settings.selectedQuestionSetID) {
                        ForEach(QuestionSet.starterSets) { set in
                            Text(set.name).tag(set.id)
                        }
                        Text("Write my own").tag("custom")
                    }

                    if settings.selectedQuestionSetID == "custom" {
                        ForEach(customPromptDrafts.indices, id: \.self) { index in
                            TextField("Question \(index + 1)", text: $customPromptDrafts[index])
                        }
                        Button("Add another question") {
                            if customPromptDrafts.count < 5 {
                                customPromptDrafts.append("")
                            }
                        }
                        .disabled(customPromptDrafts.count >= 5)
                        .onChange(of: customPromptDrafts) { _, newValue in
                            settings.customPrompts = newValue.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        }
                    }
                }
            }
        }
    }
}
