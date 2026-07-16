//
//  TTSAudioAlignment.swift
//  TTSCore
//
//  Sentence/line alignment for a single assembled utterance (VAD + proportional targets).
//

import AVFoundation
import CoreMedia
import Foundation

public struct AlignedAudioLine: Sendable, Equatable {
    public let text: String
    public let sampleRange: Range<Int>

    public init(text: String, sampleRange: Range<Int>) {
        self.text = text
        self.sampleRange = sampleRange
    }
}

public struct AlignedTimeLine: Sendable, Equatable {
    public let text: String
    public let timeRange: Range<TimeInterval>

    public init(text: String, timeRange: Range<TimeInterval>) {
        self.text = text
        self.timeRange = timeRange
    }
}

/// Fixed-duration silence inserted in Speech Studio between dialogue lines for reliable splitting.
public enum TTSAudioAlignmentMarker: Sendable {
    public static let silenceDuration: TimeInterval = 0.15
    /// Tight window so incidental ~0.13s TTS pauses are not treated as studio markers.
    public static let minimumSilenceDuration: TimeInterval = 0.145
    public static let maximumSilenceDuration: TimeInterval = 0.155
    /// Peak magnitude below this counts as studio marker silence (near-digital zero).
    public static let amplitudeThreshold: Float = 0.002

    /// Wider duration window for exported/edited clips where gaps retain low-level noise.
    public static let softMinimumSilenceDuration: TimeInterval = 0.080
    public static let softMaximumSilenceDuration: TimeInterval = 0.250
    /// RMS below this fraction of the clip peak counts as a marker valley.
    public static let softRMSValleyRatio: Float = 0.12
    public static let softMinimumRMSFloor: Float = 0.003

    public static func silenceSampleCount(sampleRate: Double) -> Int {
        max(1, Int((silenceDuration * sampleRate).rounded()))
    }
}

public enum TTSAudioFileLoaderError: Error, LocalizedError {
    case emptyFile
    case couldNotRead
    case couldNotConvert

    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "Audio file is empty."
        case .couldNotRead: return "Could not read the audio file."
        case .couldNotConvert: return "Could not convert the audio file."
        }
    }
}

public enum TTSAudioFileLoader {

    /// Reads any AVFoundation-supported file into mono Float32 samples at the file's native rate.
    public static func loadMonoFloatSamples(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        if let decoded = try? loadViaAssetReader(url), !decoded.samples.isEmpty {
            return decoded
        }
        return try loadViaAVAudioFile(url)
    }

    private static func loadViaAVAudioFile(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TTSAudioFileLoaderError.couldNotRead
        }
        guard file.length > 0 else { throw TTSAudioFileLoaderError.emptyFile }

        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TTSAudioFileLoaderError.couldNotRead
        }
        file.framePosition = 0
        try file.read(into: sourceBuffer)
        guard sourceBuffer.frameLength > 0 else { throw TTSAudioFileLoaderError.emptyFile }

        let samples = try extractMonoFloatSamples(from: sourceBuffer)
        return (samples, sourceFormat.sampleRate)
    }

    private static func loadViaAssetReader(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw TTSAudioFileLoaderError.couldNotRead
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        guard reader.startReading() else {
            throw TTSAudioFileLoaderError.couldNotRead
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { pointer in
                samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: floatCount))
            }
        }

        guard reader.status == .completed, !samples.isEmpty else {
            throw TTSAudioFileLoaderError.couldNotRead
        }
        return (samples, 24_000)
    }

    private static func extractMonoFloatSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { throw TTSAudioFileLoaderError.emptyFile }

        let channelCount = Int(buffer.format.channelCount)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else {
                throw TTSAudioFileLoaderError.couldNotConvert
            }
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
            }
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for index in 0..<frameCount {
                    mono[index] += data[index]
                }
            }
            let scale = 1.0 / Float(channelCount)
            return mono.map { $0 * scale }

        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else {
                throw TTSAudioFileLoaderError.couldNotConvert
            }
            var mono = [Float](repeating: 0, count: frameCount)
            let scale: Float = 1.0 / (32_768.0 * Float(channelCount))
            for channel in 0..<channelCount {
                let data = channels[channel]
                for index in 0..<frameCount {
                    mono[index] += Float(data[index]) * scale
                }
            }
            return mono

        default:
            throw TTSAudioFileLoaderError.couldNotConvert
        }
    }
}

public enum TTSAudioAlignment {

    /// Assigns contiguous sample ranges to `lines` inside one assembled utterance buffer.
    public static func align(lines: [String], samples: [Float], sampleRate: Double) -> [AlignedAudioLine] {
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let total = samples.count
        guard !trimmed.isEmpty, total > 0 else { return [] }

        if trimmed.count == 1 {
            return [AlignedAudioLine(text: trimmed[0], sampleRange: 0..<total)]
        }

        let weights = trimmed.map { max(1, $0.count) }
        let proportional = proportionalBoundaries(weights: weights, total: total)
        let vad = vadSpeechRegions(samples: samples, sampleRate: sampleRate)
        let gapMidpoints = midpointsBetweenVADRegions(vad)

        let boundaries: [Int]
        let skipRefinement: Bool
        if let markerBoundaries = markerSilenceBoundaries(
            samples: samples,
            sampleRate: sampleRate,
            expectedCount: trimmed.count - 1,
            proportional: proportional
        ) {
            boundaries = markerBoundaries
            skipRefinement = true
        } else if vad.count == trimmed.count {
            // One detected speech region per line: switch when the next speaker starts.
            boundaries = (1..<vad.count).map { vad[$0].lowerBound }
            skipRefinement = true
        } else if let vadGapBoundaries = vadGapBoundaries(
            vad: vad,
            weights: weights,
            samples: samples,
            sampleRate: sampleRate,
            lineCount: trimmed.count
        ) {
            // Fewer VAD regions than lines: inter-region cuts at VAD onsets, split the merged tail.
            boundaries = vadGapBoundaries
            skipRefinement = true
        } else {
            let onsetCandidates = speechOnsetCandidates(
                vad: vad,
                samples: samples,
                sampleRate: sampleRate
            )
            if onsetCandidates.count >= trimmed.count - 1 {
                boundaries = boundariesMatchingProportional(
                    proportional: proportional,
                    silenceCandidates: onsetCandidates
                )
                skipRefinement = true
            } else if gapMidpoints.count >= trimmed.count - 1 {
                boundaries = boundariesMatchingProportional(
                    proportional: proportional,
                    silenceCandidates: gapMidpoints
                )
                skipRefinement = false
            } else {
                boundaries = snapProportionalToQuietSamples(
                    proportional: proportional,
                    samples: samples,
                    sampleRate: sampleRate,
                    total: total
                )
                skipRefinement = false
            }
        }

        let refined: [Int]
        if skipRefinement {
            refined = boundaries
        } else {
            refined = refineBoundaryList(
                boundaries,
                samples: samples,
                sampleRate: sampleRate,
                total: total
            )
        }

        let ranges = contiguousRanges(boundaries: refined, total: total, count: trimmed.count)

        return zip(trimmed, ranges).map { text, range in
            AlignedAudioLine(text: text, sampleRange: range)
        }
    }

    /// Proportional time slices for one bundled clip when PCM decode is unavailable.
    public static func proportionalSegmentTimeRanges(
        lineTexts: [String],
        duration: TimeInterval
    ) -> [AlignedTimeLine] {
        let trimmed = lineTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty, duration > 0 else { return [] }

        let unitCount = max(trimmed.count, Int((duration * 1000).rounded()))
        let weights = trimmed.map { max(1, $0.count) }
        let boundaries = proportionalBoundaries(weights: weights, total: unitCount)
        let ranges = contiguousRanges(boundaries: boundaries, total: unitCount, count: trimmed.count)

        return zip(trimmed, ranges).map { text, range in
            let start = duration * Double(range.lowerBound) / Double(unitCount)
            let end = duration * Double(range.upperBound) / Double(unitCount)
            return AlignedTimeLine(text: text, timeRange: start..<max(start, end))
        }
    }

    /// VAD alignment when PCM is available; embedded M4A metadata wins when present.
    public static func segmentTimeRanges(
        lineTexts: [String],
        duration: TimeInterval,
        samples: [Float]? = nil,
        sampleRate: Double = 24_000,
        audioURL: URL? = nil
    ) -> [AlignedTimeLine] {
        if let audioURL,
           let embedded = DialogueAlignmentMetadata.readLineSwitchSeconds(from: audioURL),
           let aligned = DialogueAlignmentMetadata.segmentTimeRanges(
               lineTexts: lineTexts,
               duration: duration,
               lineSwitchSeconds: embedded
           ) {
            return aligned
        }

        if let samples, !samples.isEmpty, sampleRate > 0 {
            return align(lines: lineTexts, samples: samples, sampleRate: sampleRate).map { line in
                AlignedTimeLine(
                    text: line.text,
                    timeRange: timeRange(
                        from: line.sampleRange,
                        sampleRate: sampleRate,
                        duration: duration,
                        tailPad: 0.06
                    )
                )
            }
        }
        return dialogueSegmentTimeRanges(lineTexts: lineTexts, duration: duration)
    }

    /// Proportional split with extra tail room so lines are not cut off early.
    public static func dialogueSegmentTimeRanges(
        lineTexts: [String],
        duration: TimeInterval
    ) -> [AlignedTimeLine] {
        var lines = proportionalSegmentTimeRanges(lineTexts: lineTexts, duration: duration)
        guard lines.count >= 2, duration > 0 else { return lines }

        let minimumTailPad: TimeInterval = 0.16
        for index in 0..<(lines.count - 1) {
            let current = lines[index]
            let nextStart = lines[index + 1].timeRange.lowerBound
            let paddedEnd = min(
                duration,
                max(current.timeRange.upperBound + minimumTailPad, nextStart + minimumTailPad * 0.35)
            )
            lines[index] = AlignedTimeLine(
                text: current.text,
                timeRange: current.timeRange.lowerBound..<paddedEnd
            )
        }

        if var last = lines.last {
            last = AlignedTimeLine(
                text: last.text,
                timeRange: last.timeRange.lowerBound..<duration
            )
            lines[lines.count - 1] = last
        }
        return lines
    }

    private static func timeRange(
        from sampleRange: Range<Int>,
        sampleRate: Double,
        duration: TimeInterval,
        tailPad: TimeInterval
    ) -> Range<TimeInterval> {
        let start = Double(sampleRange.lowerBound) / sampleRate
        var end = Double(sampleRange.upperBound) / sampleRate + tailPad
        end = min(duration, end)
        return start..<max(start, end)
    }

    private static func contiguousRanges(boundaries: [Int], total: Int, count: Int) -> [Range<Int>] {
        var starts: [Int] = [0] + boundaries
        var ends: [Int] = boundaries + [total]
        for i in 0..<starts.count {
            if i > 0, starts[i] <= ends[i - 1] { starts[i] = ends[i - 1] }
            if ends[i] <= starts[i] { ends[i] = min(total, starts[i] + 1) }
            if starts[i] >= total { starts[i] = max(0, total - 1) }
            if ends[i] > total { ends[i] = total }
        }
        return (0..<count).map { i in
            let lo = max(0, min(total, starts[i]))
            let hi = max(lo, min(total, ends[i]))
            return lo..<hi
        }
    }

    // MARK: - Alignment helpers

    /// Studio marker gaps (strict digital silences only). Soft RMS valleys are diagnostic-only.
    public static func detectedMarkerSilenceRuns(
        samples: [Float],
        sampleRate: Double
    ) -> [Range<Int>] {
        strictMarkerSilenceRuns(samples: samples, sampleRate: sampleRate)
    }

    /// Quiet RMS valleys that may look like line breaks but often fall inside speech.
    public static func detectedSoftMarkerValleys(
        samples: [Float],
        sampleRate: Double
    ) -> [Range<Int>] {
        softMarkerSilenceRuns(samples: samples, sampleRate: sampleRate)
    }

    /// Studio break-suggestion lead-in: how far a suggested line-switch mark is
    /// backed off from the next speaker's detected onset.
    public static let suggestedBreakLeadInSeconds: TimeInterval = 0.08

    /// Shifts each boundary (defined by every producer as the next line's onset)
    /// earlier by up to `leadInSeconds`, but never past the start of the quiet
    /// gap in front of it — so a mark backs into silence, never into the
    /// previous speaker's audio, even when the gap is shorter than the lead-in.
    public static func leadInAdjustedBoundaries(
        _ boundaries: [Int],
        samples: [Float],
        sampleRate: Double,
        leadInSeconds: TimeInterval = suggestedBreakLeadInSeconds
    ) -> [Int] {
        guard !boundaries.isEmpty, samples.count > 1, sampleRate > 0 else { return boundaries }

        let leadInSamples = max(0, Int(leadInSeconds * sampleRate))
        let maxScanSamples = Int(sampleRate * 0.5)
        let windowSamples = max(1, Int(sampleRate * 0.010))
        let quietThreshold = quietRMSThreshold(samples: samples, windowSamples: windowSamples)

        var out: [Int] = []
        out.reserveCapacity(boundaries.count)
        for boundary in boundaries {
            let onset = min(max(boundary, 1), samples.count - 1)
            // Walk back through the quiet gap to find where the previous
            // speaker actually stopped.
            var quietRunStart = onset
            while quietRunStart > 0, onset - quietRunStart < maxScanSamples {
                let lo = max(0, quietRunStart - windowSamples)
                if rmsOfSlice(samples, lo..<quietRunStart) >= quietThreshold { break }
                quietRunStart = lo
            }
            var adjusted = max(onset - leadInSamples, quietRunStart, 1)
            if let previous = out.last { adjusted = max(adjusted, previous + 1) }
            out.append(min(adjusted, samples.count - 1))
        }
        return out
    }

    /// Same derivation as `vadSpeechRegions`' exit threshold, over 10ms windows.
    private static func quietRMSThreshold(samples: [Float], windowSamples: Int) -> Float {
        var rms: [Float] = []
        rms.reserveCapacity(samples.count / windowSamples + 1)
        var i = 0
        while i < samples.count {
            let end = min(i + windowSamples, samples.count)
            rms.append(rmsOfSlice(samples, i..<end))
            i = end
        }
        let sorted = rms.sorted()
        guard let maxRms = sorted.last else { return 0.003 }
        let floorIdx = max(0, min(sorted.count - 1, Int(Double(sorted.count) * 0.10)))
        let floor = sorted[floorIdx]
        return max(floor * 1.6, floor + (maxRms - floor) * 0.04, 0.003)
    }

    private static func rmsOfSlice(_ samples: [Float], _ range: Range<Int>) -> Float {
        guard !range.isEmpty else { return 0 }
        var sum: Float = 0
        for index in range {
            let s = samples[index]
            sum += s * s
        }
        return sqrtf(sum / Float(range.count))
    }

    /// Sample indices where the next dialogue line begins (end of each marker gap).
    private static func markerSilenceBoundaries(
        samples: [Float],
        sampleRate: Double,
        expectedCount: Int,
        proportional: [Int]
    ) -> [Int]? {
        guard expectedCount > 0 else { return [] }
        let runs = strictMarkerSilenceRuns(samples: samples, sampleRate: sampleRate)
        guard !runs.isEmpty else { return nil }

        let candidates = runs.map(\.upperBound)
        if candidates.count == expectedCount {
            return candidates
        }
        guard candidates.count > expectedCount else { return nil }
        return boundariesMatchingProportional(
            proportional: proportional,
            silenceCandidates: candidates
        )
    }

    /// When VAD finds fewer regions than lines, cut at each inter-region onset and split the tail region.
    private static func vadGapBoundaries(
        vad: [Range<Int>],
        weights: [Int],
        samples: [Float],
        sampleRate: Double,
        lineCount: Int
    ) -> [Int]? {
        guard vad.count >= 2, vad.count < lineCount else { return nil }

        var boundaries: [Int] = []
        for index in 1..<vad.count {
            boundaries.append(vad[index].lowerBound)
        }

        let linesInLastRegion = lineCount - (vad.count - 1)
        guard linesInLastRegion > 1, let lastRegion = vad.last else { return boundaries }

        let weightsInLast = Array(weights.suffix(linesInLastRegion))
        let localProportional = proportionalBoundaries(weights: weightsInLast, total: lastRegion.count)
        let absProportional = localProportional.map { lastRegion.lowerBound + $0 }

        let minSpeechSamples = max(1, Int(sampleRate * 0.040))
        let gapEnds = silenceGapEnds(
            in: lastRegion,
            samples: samples,
            sampleRate: sampleRate,
            minGapSeconds: 0.120
        ).filter { $0 > lastRegion.lowerBound + minSpeechSamples }

        let innerCandidates: [Int]
        if gapEnds.count >= absProportional.count {
            // Switch after the gap ends — avoids firing on brief dips still inside the prior line.
            innerCandidates = gapEnds
        } else {
            let slice = Array(samples[lastRegion.lowerBound..<lastRegion.upperBound])
            let subsegments = vadSpeechRegions(
                samples: slice,
                sampleRate: sampleRate,
                minSilenceSeconds: 0.080,
                minSpeechSeconds: 0.040
            )
            innerCandidates = subsegments.compactMap { sub -> Int? in
                let onset = lastRegion.lowerBound + sub.lowerBound
                return onset > lastRegion.lowerBound + minSpeechSamples ? onset : nil
            }
        }

        if innerCandidates.count >= absProportional.count {
            boundaries.append(contentsOf: boundariesMatchingProportional(
                proportional: absProportional,
                silenceCandidates: innerCandidates
            ))
        } else {
            boundaries.append(contentsOf: absProportional)
        }
        return boundaries
    }

    /// Sample indices where speech resumes after a quiet gap (upper bound of each gap).
    private static func silenceGapEnds(
        in sampleRange: Range<Int>,
        samples: [Float],
        sampleRate: Double,
        minGapSeconds: Double
    ) -> [Int] {
        guard sampleRange.lowerBound >= 0,
              sampleRange.upperBound <= samples.count,
              sampleRange.lowerBound < sampleRange.upperBound else { return [] }

        let windowSamples = max(1, Int(sampleRate * 0.020))
        let minGapSamples = max(1, Int(sampleRate * minGapSeconds))
        let region = Array(samples[sampleRange.lowerBound..<sampleRange.upperBound])

        var windows: [(start: Int, end: Int, rms: Float)] = []
        windows.reserveCapacity(region.count / windowSamples + 1)
        var index = 0
        while index < region.count {
            let end = min(index + windowSamples, region.count)
            var sum: Float = 0
            var j = index
            while j < end {
                let sample = region[j]
                sum += sample * sample
                j += 1
            }
            windows.append((start: index, end: end, rms: sqrtf(sum / Float(end - index))))
            index = end
        }
        guard !windows.isEmpty else { return [] }

        let maxRMS = windows.map(\.rms).max() ?? 0
        let threshold = max(0.003, maxRMS * 0.20)

        var gapEnds: [Int] = []
        var inGap = false
        var gapStart = 0

        for window in windows {
            if window.rms < threshold {
                if !inGap {
                    gapStart = window.start
                    inGap = true
                }
            } else if inGap {
                let gapEnd = window.start
                if gapEnd - gapStart >= minGapSamples {
                    gapEnds.append(sampleRange.lowerBound + gapEnd)
                }
                inGap = false
            }
        }
        return gapEnds
    }

    private static func strictMarkerSilenceRuns(
        samples: [Float],
        sampleRate: Double
    ) -> [Range<Int>] {
        let minSamples = max(1, Int((TTSAudioAlignmentMarker.minimumSilenceDuration * sampleRate).rounded()))
        let maxSamples = max(minSamples, Int((TTSAudioAlignmentMarker.maximumSilenceDuration * sampleRate).rounded()))
        let threshold = TTSAudioAlignmentMarker.amplitudeThreshold

        var runs: [Range<Int>] = []
        var inSilence = false
        var start = 0

        for index in samples.indices {
            let quiet = abs(samples[index]) < threshold
            if quiet {
                if !inSilence {
                    start = index
                    inSilence = true
                }
            } else if inSilence {
                let length = index - start
                if length >= minSamples, length <= maxSamples,
                   isFlatMarkerSilence(samples: samples, range: start..<index) {
                    runs.append(start..<index)
                }
                inSilence = false
            }
        }
        return runs
    }

    /// Quiet RMS valleys roughly marker-length — catches edited/exported gaps that are not digital zero.
    private static func softMarkerSilenceRuns(
        samples: [Float],
        sampleRate: Double
    ) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }

        let windowSamples = max(1, Int(sampleRate * 0.020))
        let minSamples = max(1, Int((TTSAudioAlignmentMarker.softMinimumSilenceDuration * sampleRate).rounded()))
        let maxSamples = max(minSamples, Int((TTSAudioAlignmentMarker.softMaximumSilenceDuration * sampleRate).rounded()))

        var windows: [(start: Int, end: Int, rms: Float)] = []
        windows.reserveCapacity(samples.count / windowSamples + 1)
        var index = 0
        while index < samples.count {
            let end = min(index + windowSamples, samples.count)
            var sum: Float = 0
            var j = index
            while j < end {
                let sample = samples[j]
                sum += sample * sample
                j += 1
            }
            windows.append((start: index, end: end, rms: sqrtf(sum / Float(end - index))))
            index = end
        }
        guard !windows.isEmpty else { return [] }

        let maxRMS = windows.map(\.rms).max() ?? 0
        let threshold = max(
            TTSAudioAlignmentMarker.softMinimumRMSFloor,
            maxRMS * TTSAudioAlignmentMarker.softRMSValleyRatio
        )

        var runs: [Range<Int>] = []
        var inValley = false
        var valleyStart = 0

        for window in windows {
            if window.rms < threshold {
                if !inValley {
                    valleyStart = window.start
                    inValley = true
                }
            } else if inValley {
                let valleyEnd = window.start
                let length = valleyEnd - valleyStart
                if length >= minSamples, length <= maxSamples {
                    runs.append(valleyStart..<valleyEnd)
                }
                inValley = false
            }
        }
        return runs
    }

    private static func isFlatMarkerSilence(samples: [Float], range: Range<Int>) -> Bool {
        let threshold = TTSAudioAlignmentMarker.amplitudeThreshold
        for index in range {
            if abs(samples[index]) >= threshold { return false }
        }
        return true
    }

    /// Sample indices where a new line begins speaking — VAD region onsets plus intra-region sub-segments.
    private static func speechOnsetCandidates(
        vad: [Range<Int>],
        samples: [Float],
        sampleRate: Double
    ) -> [Int] {
        guard !vad.isEmpty else { return [] }
        var candidates: [Int] = []

        for index in 1..<vad.count {
            candidates.append(vad[index].lowerBound)
        }

        for region in vad.dropFirst() {
            let slice = Array(samples[region.lowerBound..<region.upperBound])
            guard !slice.isEmpty else { continue }
            let subsegments = vadSpeechRegions(
                samples: slice,
                sampleRate: sampleRate,
                minSilenceSeconds: 0.080,
                minSpeechSeconds: 0.040
            )
            for sub in subsegments {
                candidates.append(region.lowerBound + sub.lowerBound)
            }
        }

        return Array(Set(candidates)).sorted()
    }

    private static func proportionalBoundaries(weights: [Int], total: Int) -> [Int] {
        let n = weights.count
        guard n >= 2, total > 0 else { return [] }
        let totalW = weights.reduce(0, +)
        guard totalW > 0 else { return [] }
        var cuts: [Int] = []
        cuts.reserveCapacity(n - 1)
        var cum = 0
        for i in 0..<(n - 1) {
            cum += weights[i]
            let r = Double(cum) / Double(totalW)
            let c = Int((Double(total) * r).rounded())
            cuts.append(min(max(0, c), total - 1))
        }
        for i in 1..<cuts.count where cuts[i] <= cuts[i - 1] {
            cuts[i] = min(total - 1, cuts[i - 1] + 1)
        }
        return cuts
    }

    private static func midpointsBetweenVADRegions(_ vad: [Range<Int>]) -> [Int] {
        guard vad.count >= 2 else { return [] }
        var out: [Int] = []
        out.reserveCapacity(vad.count - 1)
        for i in 0..<(vad.count - 1) {
            out.append((vad[i].upperBound + vad[i + 1].lowerBound) / 2)
        }
        return out
    }

    private static func boundariesMatchingProportional(
        proportional: [Int],
        silenceCandidates: [Int]
    ) -> [Int] {
        let k = proportional.count
        guard k > 0 else { return [] }
        let mids = Array(Set(silenceCandidates)).sorted()
        let m = mids.count
        guard m >= k else { return proportional }

        let inf = Int.max / 8
        var dp = Array(repeating: Array(repeating: inf, count: m), count: k)
        var trace = Array(repeating: Array(repeating: -1, count: m), count: k)

        for j in 0..<m {
            dp[0][j] = abs(mids[j] - proportional[0])
        }
        for i in 1..<k {
            for j in i..<m {
                var best = inf
                var bestPrev = -1
                for p in (i - 1)..<j {
                    let v = dp[i - 1][p] + abs(mids[j] - proportional[i])
                    if v < best {
                        best = v
                        bestPrev = p
                    }
                }
                dp[i][j] = best
                trace[i][j] = bestPrev
            }
        }

        var endIdx = k - 1
        var bestTotal = inf
        for j in (k - 1)..<m where dp[k - 1][j] < bestTotal {
            bestTotal = dp[k - 1][j]
            endIdx = j
        }

        var path: [Int] = []
        var j = endIdx
        for i in stride(from: k - 1, through: 0, by: -1) {
            path.append(mids[j])
            if i > 0 { j = trace[i][j] }
        }
        path.reverse()
        return path
    }

    private static func snapProportionalToQuietSamples(
        proportional: [Int],
        samples: [Float],
        sampleRate: Double,
        total: Int
    ) -> [Int] {
        guard !proportional.isEmpty, !samples.isEmpty else { return proportional }
        let searchHalf = max(1, Int(sampleRate * 0.48))
        let win = max(1, Int(sampleRate * 0.022))
        let minSep = max(320, Int(sampleRate * 0.045))
        var out: [Int] = []
        out.reserveCapacity(proportional.count)
        var lastCut = 0
        for (idx, p) in proportional.enumerated() {
            let tailSlots = proportional.count - idx
            let lo = max(lastCut + minSep, p - searchHalf)
            let hi = min(total - tailSlots * minSep, p + searchHalf)
            let chosen: Int
            if lo < hi {
                chosen = argminAverageAbs(samples: samples, lo: lo, hi: hi - 1, window: win)
            } else {
                chosen = min(max(lastCut + minSep, p), total - 1)
            }
            out.append(chosen)
            lastCut = chosen
        }
        return out
    }

    private static func argminAverageAbs(samples: [Float], lo: Int, hi: Int, window: Int) -> Int {
        guard lo <= hi, lo >= 0, hi < samples.count else {
            return min(max(0, lo), max(0, samples.count - 1))
        }
        var bestIdx = (lo + hi) / 2
        var bestE: Float = .greatestFiniteMagnitude
        let step = max(1, window / 3)
        var i = lo
        while i <= hi {
            let a = max(lo, i - window / 2)
            let b = min(samples.count - 1, i + window / 2)
            var sum: Float = 0
            var cnt = 0
            var k = a
            while k <= b {
                sum += abs(samples[k])
                cnt += 1
                k += 1
            }
            let e = cnt > 0 ? sum / Float(cnt) : .greatestFiniteMagnitude
            if e < bestE {
                bestE = e
                bestIdx = i
            }
            i += step
        }
        return bestIdx
    }

    private static func refineBoundaryList(
        _ cuts: [Int],
        samples: [Float],
        sampleRate: Double,
        total: Int
    ) -> [Int] {
        guard !cuts.isEmpty else { return cuts }
        let minPad = max(240, Int(sampleRate * 0.028))
        let refineHalf = max(1, Int(sampleRate * 0.11))
        let win = max(1, Int(sampleRate * 0.020))
        var out = cuts
        for i in out.indices {
            let prevBound = i == 0 ? 0 : out[i - 1]
            let nextBound = i == out.count - 1 ? total : cuts[i + 1]
            let clampLo = min(max(minPad, prevBound + minPad), total - minPad - 1)
            let clampHi = max(min(total - minPad, nextBound - minPad), clampLo + 1)
            let approx = out[i]
            let lo = max(clampLo, approx - refineHalf)
            let hi = min(clampHi - 1, approx + refineHalf)
            if lo < hi {
                out[i] = argminAverageAbs(samples: samples, lo: lo, hi: hi, window: win)
            }
        }
        for i in 1..<out.count where out[i] <= out[i - 1] {
            out[i] = min(total - 1, out[i - 1] + minPad)
        }
        return out
    }

    public static func vadSpeechRegions(
        samples: [Float],
        sampleRate: Double,
        minSilenceSeconds: Double = 0.180,
        minSpeechSeconds: Double = 0.060
    ) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        let windowSamples = max(1, Int(sampleRate * 0.020))
        let minSilenceSamples = max(1, Int(sampleRate * minSilenceSeconds))
        let minSpeechSamples = max(1, Int(sampleRate * minSpeechSeconds))

        var rms: [Float] = []
        rms.reserveCapacity(samples.count / windowSamples + 1)
        var i = 0
        while i < samples.count {
            let end = min(i + windowSamples, samples.count)
            var sum: Float = 0
            var j = i
            while j < end {
                let s = samples[j]
                sum += s * s
                j += 1
            }
            rms.append(sqrtf(sum / Float(end - i)))
            i = end
        }
        guard !rms.isEmpty else { return [] }

        let sorted = rms.sorted()
        let floorIdx = max(0, min(sorted.count - 1, Int(Double(sorted.count) * 0.10)))
        let maxRms = sorted.last ?? 0
        let floor = sorted[floorIdx]
        let enterThreshold = max(floor * 2.5, floor + (maxRms - floor) * 0.08, 0.005)
        let exitThreshold = max(floor * 1.6, floor + (maxRms - floor) * 0.04, 0.003)

        var regions: [Range<Int>] = []
        var inSpeech = false
        var regionStart = 0
        var silenceRun = 0
        for (k, r) in rms.enumerated() {
            let sampleStart = k * windowSamples
            let sampleEnd = min(samples.count, sampleStart + windowSamples)

            if inSpeech {
                if r < exitThreshold {
                    silenceRun += (sampleEnd - sampleStart)
                    if silenceRun >= minSilenceSamples {
                        let regionEnd = sampleStart - (silenceRun - (sampleEnd - sampleStart))
                        let adjustedEnd = max(regionStart + 1, regionEnd)
                        regions.append(regionStart..<adjustedEnd)
                        inSpeech = false
                        silenceRun = 0
                    }
                } else {
                    silenceRun = 0
                }
            } else if r >= enterThreshold {
                regionStart = sampleStart
                inSpeech = true
                silenceRun = 0
            }
        }
        if inSpeech {
            regions.append(regionStart..<samples.count)
        }

        return regions.filter { $0.count >= minSpeechSamples }
    }
}
