import AVFoundation
import Foundation

/// The short tone after an answer in the voice mode (mockup SP5a): listening starts once it has played.
@MainActor
protocol ToneSounding: AnyObject {
    /// Plays the tone and calls `completion` exactly once, also when playing fails or is stopped.
    func play(completion: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class SystemTonePlayer: NSObject, ToneSounding, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (@MainActor () -> Void)?

    func play(completion: @escaping @MainActor () -> Void) {
        stop()
        self.completion = completion
        guard let player = try? AVAudioPlayer(data: Self.chime) else { return finish() }
        player.delegate = self
        player.volume = 0.6
        self.player = player
        if !player.play() { finish() }
    }

    func stop() {
        player?.stop()
        finish()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    private func finish() {
        player = nil
        let completion = completion
        self.completion = nil
        completion?()
    }

    /// Two soft rising notes, about a third of a second, as 16-bit PCM WAV.
    static let chime: Data = {
        let rate = 44_100
        var samples: [Int16] = []
        for (frequency, duration) in [(880.0, 0.14), (1_318.5, 0.2)] {
            let count = Int(Double(rate) * duration)
            for index in 0..<count {
                let time = Double(index) / Double(rate)
                let attack = min(1, time / 0.01)
                let release = min(1, Double(count - index) / (Double(rate) * 0.06))
                let value = sin(2 * .pi * frequency * time) * 0.3 * attack * release
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        return VoiceDiagnostics.wav(samples: samples, sampleRate: rate)
    }()
}
