import SwiftUI

/// A row slider that reads its live level itself. Meters update 24 times a
/// second; observing them here keeps those redraws inside the slider instead
/// of re-rendering the whole panel.
struct SoundMeteredSlider: View {
    @ObservedObject var meters: SoundMeters
    let appID: String
    let value: Double
    let label: String
    let onChange: (Double) -> Void

    var body: some View {
        let level = meters.levels[appID]
        SoundSlider(value: value, level: level ?? 0, showsLevel: level != nil, label: label, onChange: onChange)
    }
}
