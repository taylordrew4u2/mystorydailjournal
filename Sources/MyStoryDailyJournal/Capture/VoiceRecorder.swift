import Foundation
import Speech
import AVFoundation

/// On-device speech-to-text for capture surface #3 (§5). Transcription is
/// forced on-device (`requiresOnDeviceRecognition = true`) — nothing about
/// what the user says leaves the phone, matching the rest of the app's
/// on-device-only processing story (§12).
///
/// Note: on-device recognition isn't available for every locale; if the
/// current locale doesn't support it, `start()` surfaces `authorizationDenied`
/// rather than silently falling back to server-side recognition.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var transcript = ""
    @Published var authorizationDenied = false

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            authorizationDenied = true
            return
        }

        let speechGranted = await requestSpeechAuthorization()
        let micGranted = await requestMicrophoneAuthorization()
        guard speechGranted, micGranted else {
            authorizationDenied = true
            return
        }

        do {
            try beginRecording(with: recognizer)
        } catch {
            isRecording = false
        }
    }

    private func beginRecording(with recognizer: SFSpeechRecognizer) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
