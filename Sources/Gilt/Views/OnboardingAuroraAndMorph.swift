import SwiftUI

/// Animated aurora layer for onboarding hero moments.
struct OnboardingAuroraLayer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let driftA = sin(t * 0.22)
            let driftB = cos(t * 0.18)
            let driftC = sin(t * 0.16 + 1.2)

            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.41, blue: 0.42).opacity(0.28),
                                Color(red: 0.98, green: 0.80, blue: 0.33).opacity(0.18),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 760, height: 320)
                    .blur(radius: 52)
                    .offset(x: CGFloat(driftA) * 120 - 230, y: -200)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.24, green: 0.82, blue: 0.64).opacity(0.25),
                                Color(red: 0.27, green: 0.58, blue: 0.98).opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 820, height: 360)
                    .blur(radius: 56)
                    .offset(x: CGFloat(driftB) * 130 + 180, y: -140)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.39, blue: 0.92).opacity(0.22),
                                Color(red: 0.40, green: 0.52, blue: 0.96).opacity(0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 760, height: 320)
                    .blur(radius: 60)
                    .offset(x: CGFloat(driftC) * 100, y: -250)
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}
