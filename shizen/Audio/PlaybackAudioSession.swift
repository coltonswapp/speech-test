//
//  PlaybackAudioSession.swift
//  shizen
//
//  Activates AVAudioSession for bundled clips and on-device speech without
//  interrupting background audio (podcasts, music).
//

import AVFoundation

enum PlaybackAudioSession {
    /// Ensures the shared session can route app playback to the speaker.
    ///
    /// Must run on the main thread: `AVAudioSession` touches UIKit internally,
    /// and Main Thread Checker flags `setCategory` / `setActive` off-main.
    ///
    /// When a tutor capture session is already active (``.playAndRecord``), only
    /// reactivates it so the mic stays live. Otherwise configures ``.playback``
    /// with ``.mixWithOthers``.
    static func activateForPlayback() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord {
            try session.setActive(true, options: [])
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            return
        }
        if session.category != .playback
            || session.mode != .spokenAudio
            || !session.categoryOptions.contains(.mixWithOthers)
        {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        }
        try session.setActive(true, options: [])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    /// Warm the session while the screen is idle so a later play-time
    /// ``activateForPlayback`` is a cheap `setActive` instead of a cold ~100ms IPC.
    static func prewarm() {
        if Thread.isMainThread {
            try? activateForPlayback()
        } else {
            DispatchQueue.main.async {
                try? activateForPlayback()
            }
        }
    }

    /// Activates on the next main-queue turn, then runs `completion` on main.
    ///
    /// Callers start line-emphasis (and similar) animations first; deferring
    /// keeps a cold `setActive` from blocking that turn. Prefer ``prewarm()``
    /// on appear so the deferred `setActive` is cheap.
    static func activateForPlayback(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let success: Bool
            do {
                try activateForPlayback()
                success = true
            } catch {
                success = false
            }
            completion(success)
        }
    }
}
