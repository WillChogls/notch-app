import Accelerate
import AppKit
import CoreAudio
import Foundation
import os

/// Real equalizer levels from a Core Audio process tap on the playing music app only (macOS 14.2+),
/// so videos and other sounds don't move the bars. Runs only while music plays. Falls back to `SimulatedLevels` when the OS is older, setup fails,
/// or the tap only ever delivers digital silence (that is what a denied permission looks like).
final class AudioTap: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notch.audiotap", qos: .userInteractive)
    private let latest = OSAllocatedUnfairLock(initialState: SIMD4<Double>())
    /// Set once real (non-zero) audio has arrived: from then on we trust the tap, even in silence.
    private let gotSignal = OSAllocatedUnfairLock(initialState: false)
    private var analyzer: BandAnalyzer?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// The `LevelSource` the bars read.
    func levels(at t: TimeInterval) -> SIMD4<Double> {
        gotSignal.withLock { $0 } ? latest.withLock { $0 } : SimulatedLevels.at(t)
    }

    private var tapped: String?

    /// Taps the app with this bundle id (re-taps when it changes); nil stops.
    /// On this Mac Spotify's audio comes from its main process, not a helper (checked 2026-11-07).
    func follow(_ bundleID: String?) {
        guard bundleID != tapped || procID == nil else { return }
        stop()
        guard let bundleID, #available(macOS 14.2, *) else { return }
        tapped = bundleID
        if !setUp(bundleID) { stop() }
    }

    /// The app's Core Audio process object. Missing until the app has opened audio output.
    private func processObject(_ bundleID: String) -> AudioObjectID? {
        guard var pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    @available(macOS 14.2, *)
    private func setUp(_ bundleID: String) -> Bool {
        guard let process = processObject(bundleID) else { return false }
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return false }

        var format = AudioStreamBasicDescription()
        guard read(tapID, kAudioTapPropertyFormat, into: &format), format.mSampleRate > 0,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return false }
        analyzer = BandAnalyzer(sampleRate: format.mSampleRate)

        var output = AudioObjectID(kAudioObjectUnknown)
        var uid: CFString = "" as CFString
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, into: &output),
              read(output, kAudioDevicePropertyDeviceUID, into: &uid) else { return false }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Equalizer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uid as String,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid as String]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                              kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else { return false }

        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.process(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), interleaved: interleaved)
        }
        guard status == noErr, let procID else { return false }
        // Starting IO is what triggers the one-time "system audio recording" permission prompt.
        return AudioDeviceStart(aggregateID, procID) == noErr
    }

    private func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapped = nil
        latest.withLock { $0 = .zero }
        gotSignal.withLock { $0 = false }
    }

    /// IO thread: mix to mono, analyse, publish.
    private func process(_ buffers: UnsafeMutableAudioBufferListPointer, interleaved: Bool) {
        guard let analyzer, let first = buffers.first, let data = first.mData else { return }
        let channels = interleaved ? Int(max(first.mNumberChannels, 1)) : buffers.count
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / (interleaved ? channels : 1)
        guard frames > 0 else { return }
        let mono = analyzer.mix(frames: frames) { out in
            if interleaved {
                let src = data.assumingMemoryBound(to: Float.self)
                for ch in 0..<channels {
                    vDSP_vadd(src + ch, vDSP_Stride(channels), out, 1, out, 1, vDSP_Length(frames))
                }
            } else {
                for b in buffers { if let p = b.mData?.assumingMemoryBound(to: Float.self) { vDSP_vadd(p, 1, out, 1, out, 1, vDSP_Length(frames)) } }
            }
            var scale = 1 / Float(channels)
            vDSP_vsmul(out, 1, &scale, out, 1, vDSP_Length(frames))
        }
        if !mono { return }
        let levels = analyzer.levels()
        if analyzer.heardSound { gotSignal.withLock { $0 = true } }
        latest.withLock { $0 = levels }
    }

    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }
}

/// 2048-point FFT over the most recent mono samples → 4 band levels (equalizer-spec.md §3–4A).
/// Not thread safe: used only from the tap's serial queue (or the self-check).
final class BandAnalyzer {
    static let size = 2048
    /// Hz ranges and gains for bass, low-mid, high-mid, treble.
    static let bands: [(lo: Double, hi: Double, gain: Double)] = [(40, 150, 1.0), (150, 600, 1.1), (600, 2500, 1.4), (2500, 10000, 1.8)]

    private let sampleRate: Double
    private var history = [Float](repeating: 0, count: size)
    private var scratch = [Float](repeating: 0, count: 8192)
    private let window: [Float]
    private let setup: FFTSetup
    private var real = [Float](repeating: 0, count: size / 2)
    private var imag = [Float](repeating: 0, count: size / 2)
    private(set) var heardSound = false

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
        setup = vDSP_create_fftsetup(vDSP_Length(log2(Double(Self.size))), FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `fill` writes `frames` mono samples into a zeroed buffer; they are appended to the history.
    func mix(frames: Int, fill: (UnsafeMutablePointer<Float>) -> Void) -> Bool {
        let n = min(frames, scratch.count)
        guard n > 0 else { return false }
        scratch.withUnsafeMutableBufferPointer { buf in
            vDSP_vclr(buf.baseAddress!, 1, vDSP_Length(n))
            fill(buf.baseAddress!)
        }
        append(scratch[0..<n])
        return true
    }

    func append<C: Collection>(_ samples: C) where C.Element == Float {
        let new = Array(samples.suffix(Self.size))
        if !heardSound, new.contains(where: { $0 != 0 }) { heardSound = true }
        history.removeFirst(new.count)
        history.append(contentsOf: new)
    }

    func levels() -> SIMD4<Double> {
        var windowed = [Float](repeating: 0, count: Self.size)
        vDSP.multiply(history, window, result: &windowed)
        var power = [Float](repeating: 0, count: Self.size / 2)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(Self.size / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Double(Self.size))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Self.size / 2))
            }
        }
        // zrip output is 2x the DFT, so |X|^2 = power / 4. Parseval + Hann power loss (0.375) give
        // band RMS = sqrt(2 * sum|X|^2 / (N^2 * 0.375)).
        let n = Double(Self.size), binHz = sampleRate / n
        var out = SIMD4<Double>()
        for (i, band) in Self.bands.enumerated() {
            let lo = max(1, Int((band.lo / binHz).rounded())), hi = min(Int(n / 2) - 1, Int((band.hi / binHz).rounded()))
            var sum = 0.0
            if hi >= lo { for k in lo...hi { sum += Double(power[k]) / 4 } }
            let rms = (2 * sum / (n * n * 0.375)).squareRoot()
            let db = 20 * log10(max(rms, 1e-9))
            let level = pow(min(max((db + 50) / 44, 0), 1), 0.8)
            out[i] = min(level * band.gain, 1)
        }
        return out
    }
}
