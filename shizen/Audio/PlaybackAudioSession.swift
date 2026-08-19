//
//  PlaybackAudioSession.swift
//  shizen
//
//  Activates AVAudioSession for bundled clips and on-device speech without
//  interrupting background audio (podcasts, music).
//

import AVFoundation

enum PlaybackAudioSession {
    private static let activationQueue = DispatchQueue(
        label: "shizen.PlaybackAudioSession.activation",
        qos: .userInitiated
    )

    /// Ensures the shared session can route app playback to the speaker.
    ///
    /// When a tutor capture session is already active (``.playAndRecord``), only
    /// reactivates it so the mic stays live. Otherwise configures ``.playback``
    /// with ``.mixWithOthers``.
    static func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord {
            try session.setActive(true, options: [])
            return
        }
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    /// Async variant for main-thread call sites: `setActive` blocks on an IPC to
    /// the media server (~100ms cold), long enough to drop frames of any animation
    /// running when playback starts. The wait happens on a serial background queue;
    /// `completion` runs on the main queue with whether activation succeeded.
    static func activateForPlayback(completion: @escaping (Bool) -> Void) {
        activationQueue.async {
            let success: Bool
            do {
                try activateForPlayback()
                success = true
            } catch {
                success = false
            }
            DispatchQueue.main.async { completion(success) }
        }
    }
}
