import Foundation
import AVFoundation

final class Microphone {
    private var engine: AVAudioEngine?
    private let queue = DispatchQueue(label: "com.afreed.codexluna.audio", qos: .userInitiated)
    private var samples: [Float] = []
    private var accepting = false
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { throw TextTarget.error("No usable microphone input is available.") }
        queue.sync { samples = []; accepting = true }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var provided = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if provided { status.pointee = .noDataNow; return nil }
                provided = true; status.pointee = .haveData; return buffer
            }
            if let conversionError { self.onError?(conversionError.localizedDescription); return }
            guard let channel = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
            let values = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            self.queue.async {
                guard self.accepting else { return }
                self.samples.append(contentsOf: values)
                let rms = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 } / Float(values.count))
                self.onLevel?(min(1, rms * 12))
            }
        }
        engine.prepare()
        do { try engine.start(); self.engine = engine }
        catch { input.removeTap(onBus: 0); queue.sync { accepting = false }; throw error }
    }

    @discardableResult func stop(discard: Bool = false) -> [Float] {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        return queue.sync {
            accepting = false
            let result = discard ? [] : samples
            samples = []
            return result
        }
    }
}

func checkCoreLogic() {
    precondition(insertionPrefix(before: "Hello", text: "world") == " ")
    precondition(insertionPrefix(before: "Hello ", text: "world") == "")
    precondition(insertionPrefix(before: "", text: "1. First") == "")
    precondition(insertionPrefix(before: "Existing text.", text: "1. First\n2. Second") == "\n")
    precondition(insertionPrefix(before: "Existing text.\n", text: "• First") == "")
    precondition(insertionPrefix(before: "Hello", text: ", world") == "")
    precondition(insertionPrefix(before: "(", text: "hello") == "")
    precondition(insertionPrefix(before: "List", text: "- Item") == "\n")
    print("PASS: sentence/list boundaries, whitespace, punctuation and empty fields")
}
