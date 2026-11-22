import Foundation

/// Equalizer state, persisted in UserDefaults (singleton settings from the schema).
/// Preset gains are our own voicings per genre — not the original app's values.
struct EQSettings: Codable, Equatable {
    static let bandFrequencies: [Double] = [60, 230, 910, 3_600, 14_000]
    static let presets: [(name: String, gains: [Double])] = [
        ("Flat",       [0, 0, 0, 0, 0]),
        ("Classical",  [3, 2, 0, 2, 3]),
        ("Jazz",       [3, 2, 1, 2, 2]),
        ("Rock",       [4, 2, -1, 2, 4]),
        ("Pop",        [2, 3, 2, 1, 2]),
        ("Hip-Hop",    [5, 4, 1, 0, 1]),
        ("Heavy Metal",[4, 1, -2, 3, 5]),
    ]

    var presetName: String = "Flat"
    var bandGains: [Double] = [0, 0, 0, 0, 0]
    /// 0...100. Mapped to a low-shelf gain in the audio graph (approximation of Android BassBoost).
    var bassBoost: Double = 0
    /// 0...100. Mapped to AVAudioUnitReverb wet/dry mix.
    var reverb: Double = 0
    /// 0...100. Stereo widening amount (approximation of Android Virtualizer).
    var virtualizer: Double = 0

    mutating func applyPreset(_ name: String) {
        guard let preset = Self.presets.first(where: { $0.name == name }) else { return }
        presetName = name
        bandGains = preset.gains
    }

    mutating func markCustom() { presetName = "Custom" }
}

@MainActor
final class EQStore: ObservableObject {
    @Published var settings: EQSettings {
        didSet { save() }
    }

    private let key = "eq.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EQSettings.self, from: data) {
            settings = decoded
        } else {
            settings = EQSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
