import SwiftUI

struct ScratchpadView: View {
    @ObservedObject var controller: Controller
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Scratch pad", systemImage: "note.text").font(Theme.body(24, .bold))
                Spacer()
                Button("Copy") { controller.copyNote() }.buttonStyle(WiseButtonStyle())
                    .disabled(controller.note.isEmpty)
            }
            Text("Type or dictate below. Notes save on this Mac.")
                .font(Theme.body(13)).foregroundStyle(Theme.secondary)
            TextEditor(text: $controller.note).font(Theme.body(17)).lineSpacing(5)
                .scrollContentBackground(.hidden).padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Theme.forest).focused($editing)
                .accessibilityLabel("Scratch pad notes")
            if !controller.noteSaveError.isEmpty {
                Text(controller.noteSaveError).font(Theme.body(12)).foregroundStyle(Theme.error)
            }
        }.padding(24).background(Theme.green).foregroundStyle(Theme.forest)
            .preferredColorScheme(.light).onAppear { editing = true }
    }
}
