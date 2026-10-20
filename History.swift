import SwiftUI

struct TranscriptEntry: Codable, Identifiable {
    let id: String
    let date: Date
    let raw: String
    let formatted: String
    let warning: String
}

struct HistoryView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcription history").font(Theme.body(21, .bold))
                Spacer()
                Text("\(controller.history.count) saved locally").font(Theme.body(12))
            }
            if !controller.historyError.isEmpty {
                Text(controller.historyError).font(Theme.body(12)).foregroundStyle(Theme.error)
            }
            if controller.history.isEmpty {
                Text("New transcriptions are saved here with raw and formatted text.")
                    .font(Theme.body(14)).foregroundStyle(Theme.secondary)
            }
            LazyVStack(spacing: 12) {
                ForEach(controller.history.reversed()) { entry in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 16) {
                            savedText("Raw", text: entry.raw)
                            savedText("Formatted", text: entry.formatted)
                            if !entry.warning.isEmpty {
                                Text(entry.warning).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                            }
                        }.padding(.top, 12)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date, format: .dateTime.month().day().hour().minute())
                                .font(Theme.body(12, .semibold)).foregroundStyle(Theme.secondary)
                            Text(entry.formatted.isEmpty ? entry.raw : entry.formatted)
                                .font(Theme.body(14)).lineLimit(2)
                        }
                    }.tint(Theme.forest).padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.foregroundStyle(Theme.forest)
    }
    private func savedText(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(Theme.body(13, .bold))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                }.buttonStyle(.plain).font(Theme.body(12, .semibold)).disabled(text.isEmpty)
            }
            Text(text.isEmpty ? "No formatted version available." : text)
                .font(Theme.body(15)).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
