import SwiftUI

enum Theme {
    static let pillIcon: NSImage = {
        guard let url = Bundle.main.url(forResource: "Status-template", withExtension: "png"), let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()
    static let appIcon: NSImage = {
        guard let url = Bundle.main.url(forResource: "Murmur-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()
    static let green = Color(red: 159/255, green: 232/255, blue: 112/255)
    static let forest = Color(red: 22/255, green: 51/255, blue: 0)
    static let forestHover = Color(red: 13/255, green: 31/255, blue: 0)
    static let ink = Color(red: 14/255, green: 15/255, blue: 12/255)
    static let secondary = Color(red: 69/255, green: 71/255, blue: 69/255)
    static let soft = Color(red: 226/255, green: 246/255, blue: 213/255)
    static let inverse = Color(red: 232/255, green: 235/255, blue: 230/255)
    static let error = Color(red: 203/255, green: 39/255, blue: 47/255)
    static let errorSurface = Color(red: 251/255, green: 234/255, blue: 234/255)
    static let border = ink.opacity(0.12157)
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .default) }
    static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

struct WiseButtonStyle: ButtonStyle {
    var secondary = false
    var inverse = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(14, .semibold))
            .foregroundStyle(inverse ? Theme.forest : (secondary ? Theme.forest : Theme.green))
            .padding(.horizontal, 20).frame(minHeight: 42)
            .background(inverse ? Theme.green : (secondary ? Theme.soft : (configuration.isPressed ? Theme.forestHover : Theme.forest)), in: Capsule())
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

struct WiseToggle: View {
    @Binding var isOn: Bool
    let label: String
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                Text(label).font(Theme.body(14, .semibold)).foregroundStyle(Theme.forest)
                Spacer()
                Capsule().fill(isOn ? Theme.green : Theme.secondary.opacity(0.15))
                    .frame(width: 44, height: 26)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(Theme.forest).frame(width: 20, height: 20).padding(3)
                    }
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(label).accessibilityValue(isOn ? "On" : "Off")
    }
}

struct AppMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: Theme.appIcon).resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
