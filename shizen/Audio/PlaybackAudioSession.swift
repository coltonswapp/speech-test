//
//  PlaybackAudioSession.swift
//  shizen
//
//  Activates AVAudioSession for bundled clips and on-device speech without
//  interrupting background audio (podcasts, music).
//

import AVFoundation
import QuartzCore

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
        } else if isKnownActive {
            // `setActive(true)` is a synchronous IPC (~20–30ms) even when the
            // session is already active, which drops frames mid-animation.
            return
        }
        observeDeactivationIfNeeded()
        try session.setActive(true, options: [])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        isKnownActive = true
    }

    /// Main-thread only. Cleared by ``noteDeactivated()``, interruptions, and
    /// media-services resets so the fast path never skips a needed activation.
    private static var isKnownActive = false
    private static var deactivationObservers: [NSObjectProtocol] = []

    /// Call after any `setActive(false)` elsewhere in the app.
    static func noteDeactivated() {
        if Thread.isMainThread {
            isKnownActive = false
        } else {
            DispatchQueue.main.async { isKnownActive = false }
        }
    }

    private static func observeDeactivationIfNeeded() {
        guard deactivationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        deactivationObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { _ in
                isKnownActive = false
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { _ in
                isKnownActive = false
            },
        ]
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
            #if DEBUG
            let start = CACurrentMediaTime()
            #endif
            do {
                try activateForPlayback()
                success = true
            } catch {
                success = false
            }
            #if DEBUG
            print(String(format: "[playback-start] session activate %.1fms", (CACurrentMediaTime() - start) * 1000))
            #endif
            completion(success)
        }
    }
}

extension AVAudioPlayer {
    /// A player's first `play()` spins up its output synchronously (~90ms on
    /// device). Call while idle so the real start is a cheap resume.
    func warmUpOutput() {
        guard !isPlaying else { return }
        let restoreVolume = volume
        let restoreTime = currentTime
        volume = 0
        play()
        pause()
        currentTime = restoreTime
        volume = restoreVolume
    }
}
