import AVFoundation
import Foundation
import MediaPlayer
import UIKit

enum RepeatMode: String, CaseIterable {
    case off, all, one
}

/// Playback through an AVAudioEngine chain: player -> EQ -> reverb -> output.
/// Bass boost is a low-band gain and virtualizer a presence/reverb blend —
/// documented approximations of the Android effects, not identical DSP.
@MainActor
final class PlayerEngine: ObservableObject {
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var levels: [Float] = Array(repeating: 0, count: 24)
    @Published var lastError: String?

    /// Injected by the app: resolve a track to a URL, and begin security-scoped access.
    var resolveURL: ((Track) -> URL?)?
    var beginAccess: ((Track) -> (() -> Void)?)?
    /// Called once per track after 10 seconds of continuous playback.
    var onPlayCounted: ((Track) -> Void)?

    var currentTrack: Track? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq: AVAudioUnitEQ
    private let reverb = AVAudioUnitReverb()
    private var audioFile: AVAudioFile?
    private var totalFrames: AVAudioFramePosition = 0
    private var startFrame: AVAudioFramePosition = 0
    private var stopAccess: (() -> Void)?
    private var timer: Timer?
    private var playSeconds: Double = 0
    private var countedCurrent = false
    private var engineConfigured = false

    init() {
        eq = AVAudioUnitEQ(numberOfBands: EQSettings.bandFrequencies.count)
        for (index, band) in eq.bands.enumerated() {
            band.frequency = Float(EQSettings.bandFrequencies[index])
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false
        }
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        setupRemoteCommands()
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: - Queue & transport

    func play(tracks: [Track], startAt index: Int) {
        queue = tracks
        currentIndex = index
        startCurrent()
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if isPlaying {
            player.pause()
            engine.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try? engine.start() }
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one { seek(to: 0); if !isPlaying { togglePlayPause() }; return }
        var nextIndex = currentIndex + 1
        if shuffle, queue.count > 1 {
            repeat { nextIndex = Int.random(in: 0..<queue.count) } while nextIndex == currentIndex
        }
        if nextIndex >= queue.count {
            if repeatMode == .all { nextIndex = 0 } else { stopPlayback(); return }
        }
        currentIndex = nextIndex
        startCurrent()
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        guard currentIndex > 0 else { seek(to: 0); return }
        currentIndex -= 1
        startCurrent()
    }

    func seek(to seconds: Double) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(seconds * sampleRate)
        schedule(from: frame)
        currentTime = seconds
        if isPlaying { player.play() }
        updateNowPlaying()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
    }

    // MARK: - EQ

    func applyEQ(_ settings: EQSettings) {
        for (index, band) in eq.bands.enumerated() {
            var gain = Float(settings.bandGains[safe: index] ?? 0)
            if index == 0 { gain += Float(settings.bassBoost) / 100 * 6 }       // bass boost -> low band
            if index == eq.bands.count - 1 { gain += Float(settings.virtualizer) / 100 * 2 } // presence lift
            band.gain = min(max(gain, -12), 12)
        }
        reverb.wetDryMix = Float(settings.reverb) * 0.5 + Float(settings.virtualizer) * 0.15
    }

    // MARK: - Internals

    private func configureEngineIfNeeded(format: AVAudioFormat) {
        if engineConfigured {
            // Reconnect with the file's format when it changes between tracks.
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(reverb)
        }
        if player.engine == nil {
            engine.attach(player)
            engine.attach(eq)
            engine.attach(reverb)
        }
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engineConfigured = true
        installTap(format: format)
    }

    private func installTap(format: AVAudioFormat) {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let bars = 24
            var newLevels: [Float] = []
            let chunk = max(count / bars, 1)
            for bar in 0..<bars {
                var sum: Float = 0
                let start = bar * chunk
                let end = min(start + chunk, count)
                for i in start..<end { sum += data[i] * data[i] }
                newLevels.append(min(sqrt(sum / Float(max(end - start, 1))) * 3, 1))
            }
            Task { @MainActor [weak self] in self?.levels = newLevels }
        }
    }

    private func startCurrent() {
        stopAccess?()
        stopAccess = nil
        player.stop()
        countedCurrent = false
        playSeconds = 0
        guard let track = currentTrack else { return }
        stopAccess = beginAccess?(track)
        guard let url = resolveURL?(track) else {
            lastError = "That file could not be found. It may have been moved or deleted."
            track.isMissing = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            totalFrames = file.length
            duration = Double(file.length) / file.processingFormat.sampleRate
            configureEngineIfNeeded(format: file.processingFormat)
            if !engine.isRunning { try engine.start() }
            schedule(from: 0)
            player.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        } catch {
            lastError = "Could not play \(track.title): \(error.localizedDescription)"
        }
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        startFrame = frame
        currentTime = Double(frame) / file.processingFormat.sampleRate
        let remaining = AVAudioFrameCount(max(totalFrames - frame, 0))
        player.stop()
        if remaining > 0 {
            player.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil) { [weak self] in
                Task { @MainActor [weak self] in self?.trackFinished() }
            }
        }
    }

    private func trackFinished() {
        // scheduleSegment completion also fires on manual stop/seek; only advance
        // when we are at (or past) the end of the file.
        guard currentTime >= duration - 0.5, duration > 0 else { return }
        if repeatMode == .one { seek(to: 0); player.play(); isPlaying = true; return }
        next()
    }

    private func stopPlayback() {
        player.stop()
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                if let nodeTime = self.player.lastRenderTime,
                   let playerTime = self.player.playerTime(forNodeTime: nodeTime),
                   let file = self.audioFile {
                    self.currentTime = Double(self.startFrame + playerTime.sampleTime) / file.processingFormat.sampleRate
                }
                self.playSeconds += 0.25
                if self.playSeconds >= 10, !self.countedCurrent, let track = self.currentTrack {
                    self.countedCurrent = true
                    self.onPlayCounted?(track)
                }
            }
        }
    }

    // MARK: - Now Playing & remote

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistDisplay,
            MPMediaItemPropertyAlbumTitle: track.albumDisplay,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artworkURL = LibraryFiles.artworkURL(for: track),
           let image = UIImage(contentsOfFile: artworkURL.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began, isPlaying { togglePlayPause() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
