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
}
