//
//  AmbienceBedPlayer.swift
//  shizen
//
//  Loops a published ambience bed independently of dialogue playback.
//

import AVFoundation

final class AmbienceBedPlayer {
    private var player: AVAudioPlayer?
    private var preparedId: String?
    private var prepareGeneration = 0
    private var shouldBePlaying = false

    func prepare(_ bed: AmbienceBedRef?) {
        guard let bed else {
            reset()
            return
        }
        if preparedId == bed.id, player != nil {
            player?.volume = bed.linearVolume
            return
        }
        prepareGeneration += 1
        let generation = prepareGeneration
        preparedId = bed.id
        player = nil
        RemoteAudioCache.ensureLocalBed(id: bed.id, remoteURL: bed.url) { [weak self] result in
            guard let self, self.prepareGeneration == generation else { return }
            switch result {
            case .success(let url):
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.numberOfLoops = -1
                    player.volume = bed.linearVolume
                    player.prepareToPlay()
                    self.player = player
                    if self.shouldBePlaying {
                        player.play()
                    }
                } catch {
                    self.player = nil
                }
            case .failure:
                self.player = nil
            }
        }
    }

    func play(fromStart: Bool) {
        shouldBePlaying = true
        if fromStart {
            player?.currentTime = 0
        }
        player?.play()
    }

    func pause() {
        shouldBePlaying = false
        player?.pause()
    }

    func stop() {
        shouldBePlaying = false
        player?.stop()
        player?.currentTime = 0
    }

    func reset() {
        stop()
        prepareGeneration += 1
        player = nil
        preparedId = nil
    }
}
