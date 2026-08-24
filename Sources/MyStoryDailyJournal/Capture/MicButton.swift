import SwiftUI

/// Tap to start/stop on-device dictation; the transcript streams into
/// `text` live as `VoiceRecorder` reports partial results.
struct MicButton: View {
    @ObservedObject var recorder: VoiceRecorder
    @Binding var text: String
    @State private var baseText = ""

    var body: some View {
        Button {
            if !recorder.isRecording {
                baseText = text
            }
            recorder.toggleRecording()
        } label: {
            Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                .font(.title2)
                .foregroundStyle(recorder.isRecording ? Color.accentColor : Color.secondary)
                .padding(14)
                .background(Circle().fill(Color.secondary.opacity(0.1)))
        }
        .onChange(of: recorder.transcript) { _, newValue in
            guard recorder.isRecording, !newValue.isEmpty else { return }
            text = baseText.isEmpty ? newValue : baseText + " " + newValue
        }
        .alert("Voice capture isn't available", isPresented: $recorder.authorizationDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow microphone and speech recognition access in Settings to use voice capture.")
        }
    }
}
