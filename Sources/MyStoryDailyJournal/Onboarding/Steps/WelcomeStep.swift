import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("My Story")
                .font(.largeTitle.weight(.semibold))
            Text("Every day gets a record. Write it yourself, or let the app quietly note what happened.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
