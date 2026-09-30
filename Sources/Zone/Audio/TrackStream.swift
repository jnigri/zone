import AVFoundation

/// Decodes a track with AVAssetReader and hands out PCM chunks for AVAudioPlayerNode.
/// AVAudioFile can't read some containers AVFoundation plays fine (e.g. Opus in .m4a
/// reports zero length), so decoding goes through the asset reader instead.
final class TrackStream {
    let format: AVAudioFormat
    let duration: TimeInterval

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Sample buffer read but not yet copied because the last chunk was full.
    private var pending: CMSampleBuffer?

    private init(asset: AVURLAsset, track: AVAssetTrack, format: AVAudioFormat, duration: TimeInterval) {
        self.asset = asset
        self.track = track
        self.format = format
        self.duration = duration
    }

    deinit {
        reader?.cancelReading()
    }

    static func open(_ url: URL) async throws -> TrackStream {
        let asset = AVURLAsset(url: url)
        let (duration, tracks) = try await asset.load(.duration, .tracks)
        guard let track = tracks.first(where: { $0.mediaType == .audio }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let source = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              source.mSampleRate > 0,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: source.mSampleRate,
                  channels: min(max(source.mChannelsPerFrame, 1), 2)
              )
        else { throw CocoaError(.fileReadCorruptFile) }

        let stream = TrackStream(asset: asset, track: track, format: format, duration: duration.seconds)
        try stream.seek(to: 0)
        return stream
    }

    /// Restarts decoding at `seconds`.
    func seek(to seconds: TimeInterval) throws {
        reader?.cancelReading()
        pending = nil

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: seconds, preferredTimescale: 48000),
            duration: .positiveInfinity
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        self.reader = reader
        self.output = output
    }

    /// Next chunk of about `frames` frames, or nil at the end of the track.
    func nextBuffer(frames: AVAudioFrameCount = 16384) -> AVAudioPCMBuffer? {
        guard let output, let first = pending ?? output.copyNextSampleBuffer() else { return nil }
        pending = nil

        let firstCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(first))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, firstCount)) else { return nil }
        append(first, to: buffer)

        while let sample = output.copyNextSampleBuffer() {
            let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            if buffer.frameLength + count > buffer.frameCapacity {
                pending = sample
                break
            }
            append(sample, to: buffer)
        }
        return buffer
    }

    private func append(_ sample: CMSampleBuffer, to buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        let offset = Int(buffer.frameLength)

        // Point a temporary buffer list at the free space after what's already in the chunk.
        let list = AudioBufferList.allocate(maximumBuffers: Int(format.channelCount))
        defer { free(list.unsafeMutablePointer) }
        for channel in 0..<list.count {
            list[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: count * UInt32(MemoryLayout<Float>.size),
                mData: channels[channel] + offset
            )
        }
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(count), into: list.unsafeMutablePointer
        )
        if status == noErr { buffer.frameLength += count }
    }
}
