import SwiftUI

struct VisualizerView: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(player.levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(height: max(4, CGFloat(level) * 64))
            }
        }
        .frame(height: 64)
        .animation(.easeOut(duration: 0.12), value: player.levels)
        .accessibilityHidden(true)
    }
}

// MARK: - S08 Now Playing

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showEQ = false
    @State private var scrubbing: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let track = player.currentTrack {
                    ArtworkView(track: track, size: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
                        .shadow(radius: 20)
                        .padding(.top, 8)

                    VisualizerView()

                    VStack(spacing: 4) {
                        Text(track.title).font(.title3.weight(.bold)).lineLimit(1)
                        Text("\(track.artistDisplay) · \(track.albumDisplay)")
                            .font(.subheadline).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }

                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { scrubbing ?? player.currentTime },
                            set: { scrubbing = $0 }
                        ), in: 0...max(player.duration, 1)) { editing in
                            if !editing, let value = scrubbing {
                                player.seek(to: value)
                                scrubbing = nil
                            }
                        }
                        HStack {
                            Text((scrubbing ?? player.currentTime).timeString)
                            Spacer()
                            Text(player.duration.timeString)
                        }
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    }

                    HStack(spacing: 28) {
                        Button { player.shuffle.toggle() } label: {
                            Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Theme.accent : Theme.textMuted)
                        }
                        .accessibilityLabel("Shuffle")
                        Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title2) }
                            .accessibilityLabel("Previous track")
                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56))
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        Button { player.next() } label: { Image(systemName: "forward.fill").font(.title2) }
                            .accessibilityLabel("Next track")
                        Button { cycleRepeat() } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .foregroundStyle(player.repeatMode == .off ? Theme.textMuted : Theme.accent)
                        }
                        .accessibilityLabel("Repeat")
                    }

                    HStack(spacing: 36) {
                        Button { track.isFavorite.toggle() } label: {
                            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(track.isFavorite ? Theme.accent : Theme.textMuted)
                        }
                        .accessibilityLabel("Favorite")
                        Button { showEQ = true } label: { Image(systemName: "slider.vertical.3") }
                            .accessibilityLabel("Equalizer")
                        Button { showQueue = true } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("Queue")
                    }
                    .font(.title3)
                    Spacer()
                } else {
                    EmptyStateView(title: "Nothing playing", message: "Pick a song from your library.")
                }
            }
            .padding()
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQueue) { QueueView() }
            .sheet(isPresented: $showEQ) { EqualizerView() }
        }
    }

    private func cycleRepeat() {
        switch player.repeatMode {
        case .off: player.repeatMode = .all
        case .all: player.repeatMode = .one
        case .one: player.repeatMode = .off
        }
    }
}

// MARK: - S09 Queue

struct QueueView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        if index == player.currentIndex {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
                        }
                        TrackRow(track: track)
                    }
                    .listRowBackground(Color.clear)
                    .onTapGesture {
                        player.play(tracks: player.queue, startAt: index)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets { player.removeFromQueue(at: offset) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Up Next")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - S10 Equalizer

struct EqualizerView: View {
    @EnvironmentObject private var eqStore: EQStore
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(EQSettings.presets, id: \.name) { preset in
                                Button(preset.name) {
                                    eqStore.settings.applyPreset(preset.name)
                                    player.applyEQ(eqStore.settings)
                                }
                                .buttonStyle(.bordered)
                                .tint(eqStore.settings.presetName == preset.name ? Theme.accent : Theme.textMuted)
                            }
                            if eqStore.settings.presetName == "Custom" {
                                Text("Custom").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
                Section("Bands") {
                    ForEach(EQSettings.bandFrequencies.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            HStack {
                                Text("\(Int(EQSettings.bandFrequencies[index])) Hz")
                                Spacer()
                                Text(String(format: "%+.0f dB", eqStore.settings.bandGains[index]))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .font(.caption)
                            Slider(value: Binding(
                                get: { eqStore.settings.bandGains[index] },
                                set: { newValue in
                                    eqStore.settings.bandGains[index] = newValue
                                    eqStore.settings.markCustom()
                                    player.applyEQ(eqStore.settings)
                                }), in: -12...12)
                        }
                    }
                }
                Section("Sound tools") {
                    effectSlider(title: "Bass boost", value: $eqStore.settings.bassBoost)
                    effectSlider(title: "Reverb", value: $eqStore.settings.reverb)
                    effectSlider(title: "Virtualizer", value: $eqStore.settings.virtualizer)
                    Text("Bass boost and virtualizer are close approximations on iOS — the Android effects have no exact equivalent here.")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Section {
                    Button("Reset to Flat", role: .destructive) {
                        eqStore.settings = EQSettings()
                        player.applyEQ(eqStore.settings)
                    }
                }
            }
            .navigationTitle("Equalizer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func effectSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(Theme.textMuted)
            }
            .font(.subheadline)
            Slider(value: value, in: 0...100)
                .onChange(of: value.wrappedValue) { _, _ in player.applyEQ(eqStore.settings) }
        }
    }
}
