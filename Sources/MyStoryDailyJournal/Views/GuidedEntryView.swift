import SwiftUI
import SwiftData

/// An open-ended sequence of prompts, one at a time, composed into the
/// entry body only after the user reviews and can lightly edit the result.
/// Never saves silently (§6, acceptance criteria).
///
/// Every question carries the day's own material with it — the photos taken
/// around that moment, the names already known — and every question is
/// followed by "how did that feel?", so the entry ends up carrying the
/// writer's emotional response and not just the facts. Finishing the
/// questions applies what was said to the whole day automatically
/// (`GuidedAnswerApplier`): addresses become place names, names become
/// tagged people, and the questions and answers are kept in the day's Notes.
struct GuidedEntryView: View {
    @Bindable var record: DayRecord
    /// When non-empty (the refinement flow on an auto-generated day), the
    /// composed entry starts from this text and the answers follow it, so
    /// the digest's facts survive alongside the user's own words.
    var baseText: String = ""
    var onSave: () -> Void = {}

    @Environment(\.modelContext) private var context

    @State private var promptQueue: [GuidedQuestion]
    @State private var answers: [String]
    @State private var feelings: [String]
    @State private var chosenNames: [[String]]
    @State private var placeChoices: [PlaceChoice?]
    /// What Maps found at each place question's coordinates, keyed by
    /// question id and loaded as that question comes up.
    @State private var nearbyPlaces: [String: [NearbyPlace]] = [:]
    @State private var currentIndex = 0
    @State private var isReviewing = false
    @State private var composedText = ""
    @State private var isWeavingRewrite = false
    @State private var responses: [GuidedResponse] = []
    /// The day's own camera roll, shown with any question that doesn't
    /// already carry photos of its own — looking at the day is half of
    /// remembering it.
    @State private var dayPhotos: [String] = []

    init(
        record: DayRecord,
        questions: [GuidedQuestion],
        baseText: String = "",
        onSave: @escaping () -> Void = {}
    ) {
        self.record = record
        self.baseText = baseText
        self.onSave = onSave
        let initialQuestions = questions.isEmpty
            ? [GuidedQuestionBuilder.continuationQuestion(after: [], signals: record.signals ?? [])]
            : questions
        _promptQueue = State(initialValue: initialQuestions)
        _answers = State(initialValue: Array(repeating: "", count: initialQuestions.count))
        _feelings = State(initialValue: Array(repeating: "", count: initialQuestions.count))
        _chosenNames = State(initialValue: Array(repeating: [], count: initialQuestions.count))
        _placeChoices = State(initialValue: Array(repeating: nil, count: initialQuestions.count))
    }

    /// Short words for the follow-up under every question — a tap is enough
    /// to give the entry a tone, and anything more specific can be typed.
    private static let feelingChips = [
        "good", "happy", "calm", "grateful", "tired", "stressed", "sad", "excited", "proud",
    ]

    var body: some View {
        if isReviewing {
            reviewStep
        } else {
            promptStep
        }
    }

    private var question: GuidedQuestion {
        promptQueue[min(currentIndex, promptQueue.count - 1)]
    }

    private var hasAnsweredAnything: Bool {
        currentResponses.contains(where: \.isAnswered)
    }

    private var promptContextTitle: String {
        let context = GuidedQuestionBuilder.contextSummary(for: record.signals ?? [])
        if context.isActive {
            return "This day has \(context.shortDescription)"
        }
        return "A quiet day, with open prompts ready"
    }

    private var promptStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(promptContextTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Prompt \(currentIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !shownPhotos.isEmpty {
                        DayPhotoStrip(assetIdentifiers: shownPhotos)
                    }

                    Text(question.text)
                        .font(.title3)

                    TextField("", text: $answers[currentIndex], axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    if question.placeSubject != nil {
                        placeOptionsSection
                    }

                    if !question.nameSuggestions.isEmpty {
                        nameSuggestionRow
                    }

                    if let feelingPrompt = question.feelingPrompt {
                        feelingSection(prompt: feelingPrompt)
                    }
                }
                .padding()
            }

            HStack {
                if currentIndex > 0 {
                    Button("Back") { currentIndex -= 1 }
                }
                Spacer()
                if hasAnsweredAnything {
                    Button("Review Entry") {
                        finish()
                    }
                }
                Button(currentIndex == promptQueue.count - 1 ? "Another Question" : "Next") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .task {
            guard dayPhotos.isEmpty else { return }
            dayPhotos = await DayPhotoLibrary.assetIdentifiers(
                for: record.date,
                timeZoneIdentifier: record.timeZoneIdentifier
            )
        }
        .task(id: currentIndex) {
            await loadNearbyPlaces()
        }
    }

    /// Defining a place is a tap, not a sentence: the venues Maps actually
    /// found at those coordinates first, then what kind of place it was,
    /// ending with the way out for a stop that was never a visit.
    private var placeOptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where was this?")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !venueOptions.isEmpty {
                chipRow(venueOptions)
            }
            chipRow(PlaceKind.options.map { PlaceChoice.kind($0) })
        }
    }

    private func chipRow(_ choices: [PlaceChoice]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.displayName) { choice in
                    chip(choice.displayName, isSelected: placeChoices[currentIndex] == choice) {
                        select(choice)
                    }
                }
            }
        }
    }

    private var venueOptions: [PlaceChoice] {
        (nearbyPlaces[question.id] ?? []).map {
            PlaceChoice.venue(name: $0.name, categoryLabel: $0.categoryLabel)
        }
    }

    /// Asks Maps what's at this question's coordinates, once per question.
    private func loadNearbyPlaces() async {
        guard let place = question.placeSubject,
              let latitude = place.latitude,
              let longitude = place.longitude,
              nearbyPlaces[question.id] == nil else { return }
        nearbyPlaces[question.id] = await PlaceLookup.nearbyPlaces(latitude: latitude, longitude: longitude)
    }

    /// Tapping an option answers the question in words too — the entry
    /// should say what the writer chose, not carry it as a hidden flag.
    /// Tapping the selected one again clears it.
    private func select(_ choice: PlaceChoice) {
        let previous = placeChoices[currentIndex]
        if previous == choice {
            placeChoices[currentIndex] = nil
            if answers[currentIndex] == choice.answerText { answers[currentIndex] = "" }
            return
        }

        placeChoices[currentIndex] = choice
        let answer = answers[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty || answer == previous?.answerText {
            answers[currentIndex] = choice.answerText
        }
    }

    /// A question's own photos when it has them — the shots from that visit
    /// or that moment — and otherwise the day's camera roll.
    private var shownPhotos: [String] {
        question.photoAssetIdentifiers.isEmpty ? dayPhotos : question.photoAssetIdentifiers
    }

    /// Names the writer already gave directly. Tapping one writes it into
    /// the answer and tags them on the day when the questions are finished.
    private var nameSuggestionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who?")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(question.nameSuggestions, id: \.self) { name in
                        chip(name, isSelected: chosenNames[currentIndex].contains(name)) {
                            toggleName(name)
                        }
                    }
                }
            }
        }
    }

    private func feelingSection(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.feelingChips, id: \.self) { feeling in
                        chip(feeling, isSelected: containsFeeling(feeling)) {
                            toggleFeeling(feeling)
                        }
                    }
                }
            }

            TextField("In your own words", text: $feelings[currentIndex], axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your entry")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isWeavingRewrite {
                Spacer()
                ProgressView("Weaving your details in…")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                TextEditor(text: $composedText)
                    .font(.system(.body, design: .serif))
                    .scrollContentBackground(.hidden)
            }

            HStack {
                Button("Back to questions") { isReviewing = false }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWeavingRewrite)
            }
        }
        .padding()
    }

    private func toggleName(_ name: String) {
        if let index = chosenNames[currentIndex].firstIndex(of: name) {
            chosenNames[currentIndex].remove(at: index)
            return
        }
        chosenNames[currentIndex].append(name)
        // The tap writes the name into the answer too, so the finished
        // entry says it rather than just carrying a hidden tag.
        let answer = answers[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer.range(of: name, options: .caseInsensitive) == nil else { return }
        answers[currentIndex] = answer.isEmpty ? name : answer + " " + name
    }

    private func containsFeeling(_ feeling: String) -> Bool {
        feelings[currentIndex]
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(feeling) == .orderedSame }
    }

    private func toggleFeeling(_ feeling: String) {
        var parts = feelings[currentIndex]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let index = parts.firstIndex(where: { $0.caseInsensitiveCompare(feeling) == .orderedSame }) {
            parts.remove(at: index)
        } else {
            parts.append(feeling)
        }
        feelings[currentIndex] = parts.joined(separator: ", ")
    }

    private func advance() {
        if currentIndex < promptQueue.count - 1 {
            currentIndex += 1
        } else {
            appendContinuationQuestion()
            currentIndex += 1
        }
    }

    private func appendContinuationQuestion() {
        let next = GuidedQuestionBuilder.continuationQuestion(
            after: currentResponses,
            signals: record.signals ?? []
        )
        promptQueue.append(next)
        answers.append("")
        feelings.append("")
        chosenNames.append([])
        placeChoices.append(nil)
    }

    /// Applies the answers to the day, then shows the composed entry. The
    /// application isn't a separate confirmation step — answering the
    /// questions *is* the confirmation.
    private func finish() {
        let outcome = GuidedAnswerApplier.apply(
            questions: promptQueue,
            responses: currentResponses,
            chosenNames: chosenNames,
            placeChoices: placeChoices,
            baseText: baseText,
            to: record,
            in: context
        )
        responses = outcome.responses
        composedText = Self.compose(baseText: outcome.baseText, responses: outcome.responses)
        isReviewing = true
        weaveAnswersIntoEntry(
            outcome.responses,
            baseText: outcome.baseText,
            omitPlaces: outcome.omittedPlaces
        )
    }

    private var currentResponses: [GuidedResponse] {
        promptQueue.enumerated().map { index, question in
            GuidedResponse(
                question: question.text,
                answer: answers[index],
                feeling: feelings[index]
            )
        }
    }

    /// Every guided completion — a fresh entry or the refinement of an
    /// auto-generated day — gets rewritten into one seamless entry with the
    /// answers woven in where they belong, not stacked as paragraphs.
    /// Best-effort: the plain composition is already on screen as the
    /// fallback, and stays if the on-device model can't run or the user
    /// went back to the questions.
    private func weaveAnswersIntoEntry(
        _ responses: [GuidedResponse],
        baseText: String,
        omitPlaces: [String] = []
    ) {
        guard !isWeavingRewrite else { return }
        let answered = responses.filter(\.isAnswered)
        guard !answered.isEmpty else { return }
        isWeavingRewrite = true

        let digest = baseText.isEmpty ? nil : baseText
        let profile = ProfileBrief.brief(for: record, in: context)
        Task {
            let woven = await DigestRewriter.weaveEntry(
                digest: digest,
                responses: answered,
                omitPlaces: omitPlaces,
                profile: profile
            )
            await MainActor.run {
                if let woven, isReviewing {
                    composedText = woven
                }
                isWeavingRewrite = false
            }
        }
    }

    /// The diary panel gets the woven entry; the Notes panel keeps the
    /// questions, answers and feelings it was woven from, alongside
    /// whatever the writer had already jotted there.
    private func save() {
        record.bodyText = composedText
        record.notesText = GuidedAnswerLog.appending(
            GuidedAnswerLog.block(
                date: record.date,
                responses: responses,
                timeZoneIdentifier: record.timeZoneIdentifier
            ),
            to: record.notesText
        )
        record.source = record.source == .autoGenerated ? .converted : .userWritten
        record.editedAt = .now
        try? context.save()
        // The writer just told the app a great deal about themselves —
        // fold it into what it knows before the next entry.
        ProfileLearner.learn(in: context)
        LiveActivityManager.refreshForToday(isJournaled: record.isUserWritten)
        onSave()
    }

    /// Joins non-empty answers into short paragraphs — the same lightweight
    /// template-composition approach the digest uses (§9).
    static func compose(answers: [String]) -> String {
        answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Refinement variant: the existing text leads, the answers follow.
    static func compose(baseText: String, answers: [String]) -> String {
        let trimmedBase = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let answerText = compose(answers: answers)
        return [trimmedBase, answerText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The fallback composition when the on-device model can't run: answers
    /// as paragraphs, each keeping the feeling that came with it.
    static func compose(baseText: String, responses: [GuidedResponse]) -> String {
        compose(baseText: baseText, answers: responses.map(\.sentence))
    }
}
