import AudioToolbox
import CoreAudio
import Foundation
import os

/// Listens to the playing app's sound through a Core Audio process tap (macOS 14.2+) and measures it
/// for the sound bars. Nothing is recorded or kept: each block of sound is measured and dropped.
///
/// The tap is private (only PancakeNotch sees it), mixes the app down to mono and doesn't change
/// what you hear. macOS asks for "System Audio Recording" the first time, and shows its purple
/// indicator while a tap runs. Setting up and taking down happen on a queue of their own (Core Audio
/// can take a moment, and must not hold up the notch); the measuring runs on Core Audio's real-time
/// thread with memory set aside up front. The main thread reads the latest levels when it wants them.
final class AudioLevelMeter: @unchecked Sendable {
    private let control = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.soundbars", qos: .userInitiated)
    private let analyzer = LevelAnalyzer()
    private let mailbox = OSAllocatedUnfairLock(initialState: MeterReading())
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "soundbars")

    // Only touched on `control`.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// The latest levels and what has been heard (main thread).
    var reading: MeterReading { mailbox.withLock { $0 } }

    /// Starts listening to these Core Audio process objects (stops any earlier tap first).
    func start(processes: [AudioObjectID]) {
        control.async { [self] in
            tearDown()
            mailbox.withLock { $0 = MeterReading() }
            do {
                try setUp(processes: processes)
            } catch {
                logger.notice("Sound bars can't listen to the playing app (\(error.localizedDescription, privacy: .public)); using gentle motion.")
                tearDown()
                mailbox.withLock { $0.failed = true }
            }
        }
    }

    func stop() {
        control.async { [self] in tearDown() }
    }

    /// Stops and waits for it (the app is quitting).
    func stopNow() {
        control.sync { tearDown() }
    }

    private struct SetUpError: LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { "\(step) failed (\(status))" }
    }

    private func setUp(processes: [AudioObjectID]) throws {
        guard !processes.isEmpty else { throw SetUpError(step: "finding the app's sound", status: 0) }
        let description = CATapDescription(monoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted
        description.name = "PancakeNotch sound bars"
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw SetUpError(step: "creating the tap", status: status) }

        // The tap's sound format: mono float at the output's sample rate.
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { throw SetUpError(step: "reading the tap's format", status: status) }
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            throw SetUpError(step: "reading the tap's format (not 32-bit float)", status: 0)
        }
        analyzer.configure(sampleRate: format.mSampleRate)

        // A private device with only the tap in it: no speakers or microphones are involved.
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PancakeNotch sound bars",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ] as [String: Any]],
        ]
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID)
        guard status == noErr else { throw SetUpError(step: "creating the listening device", status: status) }

        let analyzer = analyzer
        let mailbox = mailbox
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, _, _ in
            // Core Audio's real-time thread: measure and hand over, nothing else.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard buffers.count > 0 else { return }
            let buffer = buffers[0]
            guard let data = buffer.mData else { return }
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            analyzer.process(data.assumingMemoryBound(to: Float.self), frames: frames, stride: channels)
            let reading = analyzer.reading
            mailbox.withLock { $0 = reading }
        }
        guard status == noErr, ioProcID != nil else { throw SetUpError(step: "adding the measuring", status: status) }
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { throw SetUpError(step: "starting to listen", status: status) }
    }

    /// Takes everything down, in Core Audio's order. Safe to call when nothing is set up.
    private func tearDown() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        // No audio is processed now: safe to clear.
        analyzer.reset()
    }
}
