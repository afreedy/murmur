import SwiftUI

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(Theme.forest.opacity(granted ? 1 : 0.35))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(14, .semibold)).foregroundStyle(Theme.forest)
                Text(detail).font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            if !granted { Button("Allow", action: action).buttonStyle(WiseButtonStyle(secondary: true)) }
        }.padding(.vertical, 8)
    }
}

struct MainView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        HStack(spacing: 9) {
                            AppMark(size: 36)
                            Text("murmur").font(Theme.body(23, .bold)).tracking(-0.8)
                        }.foregroundStyle(Theme.forest)
                        Spacer()
                        Label("Audio stays on your Mac", systemImage: "lock.fill")
                            .font(Theme.body(12, .semibold)).foregroundStyle(Theme.forest)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.forest.opacity(0.07), in: Capsule())
                    }
                    if geometry.size.width >= 850 {
                        HStack(alignment: .top, spacing: 32) { introduction; setup.frame(width: 340) }
                    } else {
                        VStack(alignment: .leading, spacing: 24) { introduction; setup }
                    }
                    transcript
                    HistoryView(controller: controller)
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("Luna sends your transcript to OpenAI using your Codex account. Turn Luna off to transcribe offline.")
                    }.font(Theme.body(12)).foregroundStyle(Theme.forest.opacity(0.75))
                }.padding(32)
            }.background(Theme.green)
        }.preferredColorScheme(.light)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Dictate into\na text field.")
                .font(Theme.display(53)).tracking(-2.3).lineSpacing(-5)
                .foregroundStyle(Theme.forest).fixedSize(horizontal: false, vertical: true)
            Text("Click a text field before you start.")
                .font(Theme.body(17, .medium)).foregroundStyle(Theme.forest)
            HStack(spacing: 16) {
                Text("fn").font(Theme.body(27, .semibold))
                    .foregroundStyle(Theme.forest).frame(width: 72, height: 64)
                    .background(Theme.forest.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.forest.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Start recording").font(Theme.body(15, .bold))
                    Text("Hold Fn while speaking, then release.\nFor hands-free, press Fn + Space. Press Fn to stop.")
                        .font(Theme.body(14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Theme.forest)
            }
            Text("Luna fixes wording, punctuation and lists.\nPress Esc to cancel.")
                .font(Theme.body(13)).foregroundStyle(Theme.forest.opacity(0.75)).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(Theme.body(21, .bold)).tracking(-0.5)
                Spacer()
                AppMark(size: 30)
            }.foregroundStyle(Theme.forest)
            PermissionRow(title: "Microphone", detail: "Record speech", granted: controller.microphoneAllowed) { controller.allowMicrophone() }
            PermissionRow(title: "Accessibility", detail: "Paste into the selected text field", granted: controller.accessibilityAllowed) { controller.requestAccessibility() }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                Label(controller.localReady ? "Whisper ready" : "Loading Whisper…", systemImage: controller.localReady ? "checkmark.circle.fill" : "clock")
                Spacer()
                Text("On your Mac").foregroundStyle(Theme.secondary)
            }.font(Theme.body(12)).foregroundStyle(Theme.forest)
            WiseToggle(isOn: $controller.refineWithLuna, label: "Format with Luna")
                .disabled(controller.active)
            Text(controller.lunaReady ? "Luna ready. Formatting requires internet." : "Connecting to Luna…")
                .font(Theme.body(11)).foregroundStyle(Theme.secondary)
            HStack {
                Text("Names and terms (optional)").font(Theme.body(12, .semibold))
                Spacer()
                Label("Saved", systemImage: "checkmark.circle.fill").font(Theme.body(11))
                    .accessibilityLabel("Names and terms saved automatically on this Mac")
            }.foregroundStyle(Theme.forest)
            TextField("PostgreSQL, Prisma, NestJS", text: Binding(
                get: { controller.vocabulary }, set: { controller.setVocabulary($0) }), axis: .vertical)
                .font(Theme.body(12)).lineLimit(2...3).padding(10)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .accessibilityLabel("Names and terms").disabled(controller.active)
            Text("Saves automatically on this Mac. Helps recognize spellings, up to 500 characters.")
                .font(Theme.body(11)).foregroundStyle(Theme.secondary)
            if controller.flowRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quit Wispr Flow to let Murmur use Fn.")
                        .font(Theme.body(12)).foregroundStyle(Theme.forest)
                    Button("Quit Wispr Flow") { controller.quitFlow() }.buttonStyle(WiseButtonStyle(secondary: true))
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))
            }
            Button { controller.toggleEnabled() } label: {
                HStack { Spacer(); Text(controller.enabled ? "Pause dictation" : "Enable dictation"); Spacer() }
            }.buttonStyle(WiseButtonStyle()).disabled(!controller.enabled && !controller.canEnable)
        }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Latest transcription").font(Theme.body(21, .bold)).tracking(-0.5).foregroundStyle(Theme.green)
                    Text(controller.status).font(Theme.body(12)).foregroundStyle(Theme.inverse)
                }
                Spacer()
                HStack(spacing: 3) {
                    transcriptTab("Formatted", raw: false)
                    transcriptTab("Raw", raw: true)
                }.padding(3).background(Theme.green.opacity(0.13), in: Capsule())
                Button { controller.copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(WiseButtonStyle(inverse: true))
                    .disabled((controller.showRaw ? controller.raw : controller.refined).isEmpty)
            }
            let text = controller.showRaw ? controller.raw : controller.refined
            ScrollView {
                Text(text.isEmpty ? "Your next transcription will appear here." : text)
                    .font(Theme.body(17)).lineSpacing(6)
                    .foregroundStyle(text.isEmpty ? Theme.inverse.opacity(0.6) : Theme.inverse)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(minHeight: 120, maxHeight: 230)
            if !controller.notice.isEmpty {
                Label(controller.notice, systemImage: "exclamationmark.circle")
                    .font(Theme.body(12)).foregroundStyle(Theme.forest)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))
            }
            if controller.notice.isEmpty && !controller.lastWarning.isEmpty {
                Text("Last warning: " + controller.lastWarning)
                    .font(Theme.body(12)).foregroundStyle(Theme.inverse).textSelection(.enabled)
            }
            if !controller.timing.isEmpty {
                Text(controller.timing).font(Theme.body(11)).foregroundStyle(Theme.inverse.opacity(0.65))
            }
        }.padding(24).background(Theme.forest, in: RoundedRectangle(cornerRadius: 24))
    }

    private func transcriptTab(_ title: String, raw: Bool) -> some View {
        Button { controller.showRaw = raw } label: {
            Text(title).font(Theme.body(12, .semibold))
                .foregroundStyle(controller.showRaw == raw ? Theme.forest : Theme.green)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(controller.showRaw == raw ? Theme.green : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(controller.showRaw == raw ? .isSelected : [])
    }
}

struct MenuView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) { AppMark(size: 30); Text("murmur").font(Theme.body(19, .bold)) }
                Spacer()
                Text("fn").font(Theme.body(14, .bold)).padding(9).background(Theme.forest.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            Button("About Murmur") { controller.showAbout() }.buttonStyle(.plain)
            Text(controller.status).font(Theme.body(14, .semibold))
            if !controller.notice.isEmpty { Text(controller.notice).font(Theme.body(12)).fixedSize(horizontal: false, vertical: true) }
            Text("Hold Fn to record. Fn + Space starts hands-free.\nPress Fn to stop, or Esc to cancel.")
                .font(Theme.body(12)).foregroundStyle(Theme.secondary).lineSpacing(3)
            Button(controller.enabled ? "Pause dictation" : "Enable dictation") { controller.toggleEnabled() }
                .buttonStyle(WiseButtonStyle()).disabled(!controller.enabled && !controller.canEnable)
            HStack {
                Button("Open Murmur") { controller.showWindow() }.buttonStyle(WiseButtonStyle(secondary: true))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(WiseButtonStyle(secondary: true))
            }
        }.padding(24).frame(width: 330).foregroundStyle(Theme.forest).background(Theme.green)
            .preferredColorScheme(.light)
    }
}

struct PillControl: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 48, height: 36)
                .foregroundStyle(hovered ? Theme.forest : Theme.green)
                .background(hovered ? Theme.green : Theme.forest, in: Capsule())
                .overlay(Capsule().stroke(Theme.green.opacity(0.3), lineWidth: 1))
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(title).accessibilityLabel(title)
    }
}

struct DictationPill: View {
    @ObservedObject var controller: Controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            PillControl(icon: controller.listening ? "stop.fill" : "mic.fill",
                        title: controller.listening ? "Finish dictation" : "Start hands-free dictation") { controller.toggleHandsFree() }
                .disabled(controller.finishing || (!controller.listening && !controller.canEnable))
                .modifier(SplitControl(visible: controller.pillHovered, x: controller.active ? -268 : -112))
            PillControl(icon: "macwindow", title: "Open Murmur") { controller.showWindow() }
                .modifier(SplitControl(visible: controller.pillHovered, x: controller.active ? -212 : -56))
            PillControl(icon: "note.text", title: "Open scratch pad") { controller.showScratchpad() }
                .modifier(SplitControl(visible: controller.pillHovered, x: controller.active ? 212 : 56))
            PillControl(icon: controller.active ? "xmark" : (controller.enabled ? "pause.fill" : "play.fill"),
                        title: controller.active ? "Cancel dictation" : (controller.enabled ? "Pause dictation" : "Enable dictation")) {
                if controller.active { controller.cancelRecording() } else { controller.toggleEnabled() }
            }.disabled(!controller.active && !controller.enabled && !controller.canEnable)
                .modifier(SplitControl(visible: controller.pillHovered, x: controller.active ? 268 : 112))
            if controller.active {
                HStack(spacing: 14) {
                    if controller.listening {
                        Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold))
                    } else {
                        ProcessingRing().frame(width: 20, height: 20)
                            .accessibilityLabel("Processing dictation")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controller.listening ? (controller.handsFree ? "Recording hands-free" : "Recording") : controller.status)
                            .font(Theme.body(14, .semibold))
                        Text(controller.notice.isEmpty ? (controller.listening ? (controller.handsFree ? "Press Fn or Stop to finish" : "Release Fn to transcribe") : "The finished text will be pasted once.") : controller.notice)
                            .font(Theme.body(10)).foregroundStyle(Theme.inverse).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if controller.listening {
                        Button { controller.stopRecording() } label: {
                            Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28).background(Theme.green.opacity(0.15), in: Circle())
                        }.buttonStyle(.plain).help("Finish dictation").accessibilityLabel("Finish dictation")
                    }
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<5) { index in
                            Capsule().fill(Theme.green).frame(width: 3, height: controller.listening ? 5 + CGFloat(controller.level) * CGFloat([18, 30, 24, 34, 16][index]) : 5)
                        }
                    }.frame(width: 28, height: 36).accessibilityHidden(true)
                }.padding(.horizontal, 20).frame(width: 352, height: 60)
                    .foregroundStyle(Theme.green).background(Theme.forest, in: Capsule())
            } else {
                Button { controller.showWindow() } label: {
                    SleepingMoon(awake: controller.pillHovered)
                        .opacity(controller.enabled && controller.canEnable ? 1 : 0.55)
                        .frame(width: 76, height: 36).background(Theme.forest, in: Capsule())
                        .overlay(alignment: .trailing) {
                            if !controller.notice.isEmpty {
                                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8))
                                    .foregroundStyle(Theme.green).padding(.trailing, 3)
                            }
                        }
                }.buttonStyle(.plain)
                    .help(controller.notice.isEmpty ? "Hold Fn, Fn + Space, or hover for controls." : controller.notice)
                    .accessibilityLabel("Murmur. Hover for dictation, app and scratch pad controls.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()).onHover { controller.setPillHovered($0) }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.58), value: controller.pillHovered)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 132)
            Text("Murmur").font(Theme.display(40)).tracking(-1.2)
            Text("Dictation for your Mac").font(Theme.body(15, .medium))
            Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                .font(Theme.body(12)).foregroundStyle(Theme.secondary)
            Text("Whisper transcribes on your Mac.\nLuna formats the transcript using your Codex account.")
                .font(Theme.body(13)).lineSpacing(4).multilineTextAlignment(.center)
            Text("Luna sends text to OpenAI. Audio stays on your Mac.")
                .font(Theme.body(11)).foregroundStyle(Theme.secondary)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Theme.forest).background(Theme.green).preferredColorScheme(.light)
    }
}

struct SplitControl: ViewModifier {
    let visible: Bool
    let x: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let motionDisabled = reduceMotion
        return content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: visible) { view, scale in
            view.scaleEffect(x: motionDisabled ? 1 : scale.width, y: motionDisabled ? 1 : scale.height)
        } keyframes: { _ in
            KeyframeTrack(\.width) {
                LinearKeyframe(visible ? 1.14 : 0.9, duration: 0.12)
                SpringKeyframe(1, duration: 0.32, spring: .bouncy)
            }
            KeyframeTrack(\.height) {
                LinearKeyframe(visible ? 0.88 : 1.08, duration: 0.12)
                SpringKeyframe(1, duration: 0.32, spring: .bouncy)
            }
        }.scaleEffect(visible ? 1 : 0.5).opacity(visible ? 1 : 0)
            .offset(x: visible ? x : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
    }
}

struct ProcessingRing: View {
    @State private var rotating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Theme.green.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: 0.72).stroke(Theme.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(rotating && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
        }.onAppear { rotating = true }.accessibilityLabel("Processing dictation")
    }
}

struct SleepingMoon: View {
    let awake: Bool
    @State private var awakeSince = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = max(0, timeline.date.timeIntervalSince(awakeSince))
            let glance = elapsed.truncatingRemainder(dividingBy: 10)
            let gaze = reduceMotion ? 0 : (glance >= 2 && glance < 4 ? sin((glance - 2) * .pi / 2) : (glance >= 6 && glance < 8 ? -sin((glance - 6) * .pi / 2) : 0))
            let blinkPhase = elapsed.truncatingRemainder(dividingBy: 4.6)
            let eyeHeight = reduceMotion || blinkPhase >= 0.22 || elapsed < 1 ? 1 : max(0.12, 1 - sin(blinkPhase / 0.22 * .pi))
            ZStack {
                Image(nsImage: Theme.pillIcon).resizable().scaledToFit()
                    .frame(width: 26, height: 26)
                    .overlay {
                        if awake {
                            ZStack {
                                moonEye(x: -3.1, y: 0.5, gaze: gaze, openness: eyeHeight)
                                moonEye(x: -1.1, y: -0.5, gaze: gaze, openness: eyeHeight)
                            }
                        }
                    }
                    .rotationEffect(.degrees(awake ? -8 : 0))
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: awake)
                ForEach(0..<3) { index in
                    let progress = (time / 3.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z").font(.system(size: 8 + CGFloat(index), weight: .semibold))
                        .foregroundStyle(Theme.inverse)
                        .opacity(awake ? 0 : (reduceMotion ? (index == 1 ? 0.6 : 0) : sin(progress * .pi) * 0.65))
                        .rotationEffect(.degrees(-18))
                        .offset(x: 4 + CGFloat(progress) * 14, y: -7 - CGFloat(progress) * 8)
                }
            }.frame(width: 68, height: 32).clipped().accessibilityHidden(true)
        }.onChange(of: awake) { _, newValue in
            if newValue { awakeSince = Date() }
        }
    }
    private func moonEye(x: CGFloat, y: CGFloat, gaze: Double, openness: Double) -> some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 2.3, height: 3.4)
            Ellipse().fill(Theme.forest).frame(width: 1.25, height: 2.4 * openness)
                .offset(x: gaze * 0.35)
        }.offset(x: x, y: y)
    }
}
