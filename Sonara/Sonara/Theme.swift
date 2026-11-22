import SwiftUI

/// Design tokens from replica/design/tokens.json — views use these, never raw values.
enum Theme {
    static let bg = Color("Bg")
    static let surface = Color("Surface")
    static let surfaceRaised = Color("SurfaceRaised")
    static let textPrimary = Color("TextPrimary")
    static let textMuted = Color("TextMuted")
    static let accent = Color("Accent")
    static let onAccent = Color("OnAccent")
    static let border = Color("Border")
    static let danger = Color("Danger")

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 20
    static let spacing: CGFloat = 8
}

extension TimeInterval {
    var timeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
