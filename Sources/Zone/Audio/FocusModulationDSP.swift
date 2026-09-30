import AudioToolbox
import Foundation

/// Brain.fm-style focus modulation (Woods et al. 2024): the 200 Hz–1 kHz band of the
/// mix dips in loudness 16 times a second, following a sine; the rest passes untouched.
///
/// out = x − g(t) · bandpass(x), with g(t) = depth · (0.5 − 0.5·cos(2π·16·t)).
/// A constant-peak bandpass traces a circle through 0 and 1 in the complex plane,
/// so |1 − g·H| ≤ 1: the effect only ever attenuates, never boosts.
///
/// Render-thread safe: all storage is allocated up front, no locks.
final class FocusModulationDSP {
    static let rate: Double = 16
    static let maxChannels = 8
    private static let lowCut: Double = 200
    private static let highCut: Double = 1000

    private var phase: Double = 0
    private var phaseStep: Double = 0
    private var depth: Float = 0
    private var smoothing: Float = 0

    // Bandpass biquad (RBJ, constant 0 dB peak), transposed direct form II. b1 is 0.
    private var b0: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private let z1 = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let z2 = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)

    init(sampleRate: Double = 44100) {
        reset(sampleRate: sampleRate)
    }

    deinit {
        z1.deallocate()
        z2.deallocate()
    }

    func reset(sampleRate: Double) {
        let center = (Self.lowCut * Self.highCut).squareRoot()
        let q = center / (Self.highCut - Self.lowCut)
        let w0 = 2 * Double.pi * center / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = Float(alpha / a0)
        b2 = Float(-alpha / a0)
        a1 = Float(-2 * cos(w0) / a0)
        a2 = Float((1 - alpha) / a0)

        phaseStep = 2 * Double.pi * Self.rate / sampleRate
        // ~20 ms one-pole glide so switching on/off or changing depth never clicks.
        smoothing = Float(1 - exp(-1 / (0.02 * sampleRate)))
        z1.initialize(repeating: 0, count: Self.maxChannels)
        z2.initialize(repeating: 0, count: Self.maxChannels)
    }

    /// Processes non-interleaved float buffers in place.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int, targetDepth: Float) {
        let channels = min(buffers.count, Self.maxChannels)
        for frame in 0..<frameCount {
            depth += (targetDepth - depth) * smoothing
            let gain = depth * Float(0.5 - 0.5 * cos(phase))
            phase += phaseStep
            if phase >= 2 * Double.pi { phase -= 2 * Double.pi }

            for channel in 0..<channels {
                guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let x = data[frame]
                let band = b0 * x + z1[channel]
                z1[channel] = -a1 * band + z2[channel]
                z2[channel] = b2 * x - a2 * band
                data[frame] = x - gain * band
            }
        }
    }
}
