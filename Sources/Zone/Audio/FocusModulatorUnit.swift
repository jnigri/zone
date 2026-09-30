import AVFoundation

/// In-process effect Audio Unit wrapping FocusModulationDSP so it can sit in an AVAudioEngine graph.
final class FocusModulatorUnit: AUAudioUnit {
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("fmod"),
        componentManufacturer: fourCC("Zone"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(
            FocusModulatorUnit.self,
            as: componentDescription,
            name: "Zone: Focus Modulator",
            version: 1
        )
    }()

    static func makeNode() -> AVAudioUnitEffect {
        _ = registration
        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }

    /// Target modulation depth (0 = off). Written on main, read on the render thread.
    let targetDepth = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    private let dsp = FocusModulationDSP()
    private let input = InputBuffer()
    private var inputBus: AUAudioUnitBus
    private var outputBus: AUAudioUnitBus
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!

    /// Fallback buffers for when the host passes none; allocated in allocateRenderResources.
    private final class InputBuffer {
        var pcm: AVAudioPCMBuffer?
    }

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = AVAudioChannelCount(FocusModulationDSP.maxChannels)
        outputBus.maximumChannelCount = AVAudioChannelCount(FocusModulationDSP.maxChannels)
        targetDepth.initialize(to: 0)
        try super.init(componentDescription: componentDescription, options: options)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }

    deinit {
        targetDepth.deallocate()
    }

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        guard inputBus.format.channelCount == outputBus.format.channelCount else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        input.pcm = AVAudioPCMBuffer(pcmFormat: inputBus.format, frameCapacity: maximumFramesToRender)
        dsp.reset(sampleRate: outputBus.format.sampleRate)
    }

    override func deallocateRenderResources() {
        input.pcm = nil
        super.deallocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let dsp = dsp, input = input, targetDepth = targetDepth
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock, let pcm = input.pcm else { return kAudioUnitErr_NoConnection }
            guard frameCount <= pcm.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }

            // Process in place: pull straight into the host's output buffers,
            // lending ours first when the host passes none.
            let byteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            let outputList = UnsafeMutableAudioBufferListPointer(outputData)
            let ownList = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            for i in 0..<outputList.count {
                if outputList[i].mData == nil, i < ownList.count {
                    outputList[i].mData = ownList[i].mData
                }
                outputList[i].mDataByteSize = byteSize
            }

            var flags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&flags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            dsp.process(outputList, frameCount: Int(frameCount), targetDepth: targetDepth.pointee)
            return noErr
        }
    }
}

private func fourCC(_ code: String) -> FourCharCode {
    code.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
}
