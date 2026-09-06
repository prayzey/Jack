import SwiftUI

// MARK: - Intelligent Capture Animation
struct DataFlowCaptureAnimation: View {
    let texts = ["{ }", "IMG", "URL"]
    let backgrounds = [
        AnyShapeStyle(Color.white.opacity(0.1)),
        AnyShapeStyle(
            LinearGradient(
                colors: [Color(red: 0.82, green: 0.26, blue: 0.38), Color(red: 0.90, green: 0.34, blue: 0.44)],
                startPoint: .leading,
                endPoint: .trailing
            )
        ),
        AnyShapeStyle(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.62, blue: 0.42), Color(red: 0.24, green: 0.72, blue: 0.52)],
                startPoint: .leading,
                endPoint: .trailing
            )
        ),
    ]
    let delays: [TimeInterval] = [0.0, 1.0, 2.0]
    let xOffsets: [CGFloat] = [-40, 0, 40]
    
    var body: some View {
        ZStack {
            // Hint lines
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)).frame(width: 60, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)).frame(width: 80, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)).frame(width: 40, height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            
            ForEach(0..<3, id: \.self) { i in
                DataFlowItem(text: texts[i], background: backgrounds[i], delay: delays[i])
                    .offset(x: xOffsets[i])
            }
            
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let pulseT = t.truncatingRemainder(dividingBy: 3.0)
                let glowScale = pulseT > 2.0 && pulseT < 2.5 ? 1.0 + CGFloat(pulseT - 2.0) : 1.0
                let glowOpac = pulseT > 2.0 && pulseT < 2.5 ? 1.0 - (pulseT - 2.0) * 2.0 : 0.0
                
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 90, height: 5)
                    .offset(y: 40)
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.48, green: 0.38, blue: 0.90).opacity(glowOpac), lineWidth: 4)
                            .frame(width: 90, height: 5)
                            .scaleEffect(glowScale)
                            .offset(y: 40)
                    )
            }
        }
    }
}

struct DataFlowItem: View {
    let text: String
    let background: AnyShapeStyle
    let delay: TimeInterval
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle: TimeInterval = 3.0
            let progress = (t + delay).truncatingRemainder(dividingBy: cycle) / cycle
            
            let yOffset = progress < 0.4 ? -60 + CGFloat(progress / 0.4) * 60 :
                          progress < 0.7 ? 0 + CGFloat((progress - 0.4) / 0.3) * 35 :
                          35 + CGFloat((progress - 0.7) / 0.3) * 10
            let scale: CGFloat = progress < 0.4 ? 0.3 + CGFloat(progress / 0.4) * 0.7 :
                                 progress < 0.7 ? 1.0 - CGFloat((progress - 0.4) / 0.3) * 0.2 :
                                 0.8 - CGFloat((progress - 0.7) / 0.3) * 0.6
            let opacity: Double = progress < 0.1 ? progress / 0.1 :
                                  progress < 0.7 ? 1.0 :
                                  1.0 - ((progress - 0.7) / 0.3)
                                  
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(background)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3), lineWidth: 1))
                .scaleEffect(scale)
                .opacity(opacity)
                .offset(y: yOffset)
        }
    }
}

// MARK: - Visual History View Mode Morphing
struct VisualHistoryAnimation: View {
    @State private var modeIndex = 0
    let modes: [ViewMode] = [.tray, .grid, .drawer, .radial]
    let modeNames = ["Tray", "Grid", "Drawer", "Radial"]
    let modeColors: [Color] = [
        Color(red: 0.94, green: 0.38, blue: 0.5),
        Color(red: 0.3, green: 0.4, blue: 0.8),
        Color(red: 0.24, green: 0.72, blue: 0.52),
        Color(red: 0.94, green: 0.8, blue: 0.38)
    ]
    let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.clear // Fixes jumping width by occupying full available bounds

            Text(modeNames[modeIndex])
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(modeColors[modeIndex].opacity(0.4), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .zIndex(100)
            
            ZStack {
                VisualHistoryContainerFrame(mode: modes[modeIndex])
                
                ForEach(0..<6) { i in
                    MorphingCard(index: i, mode: modes[modeIndex])
                }
                
                Circle()
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    .background(Circle().fill(Color.yellow.opacity(0.15)))
                    .frame(width: 16, height: 16)
                    .opacity(modes[modeIndex] == .radial ? 1 : 0)
            }
            .frame(width: 0, height: 0) // Strictly prevents container expansion
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: modeIndex)
        .onReceive(timer) { _ in
            modeIndex = (modeIndex + 1) % modes.count
        }
        .onAppear {
            modeIndex = 0
        }
    }
}

struct VisualHistoryContainerFrame: View {
    let mode: ViewMode
    
    var body: some View {
        ZStack {
            if mode == .tray {
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 220, height: 50)
                    .offset(y: 40)
            } else if mode == .grid {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 180, height: 110)
                    .shadow(color: .black.opacity(0.5), radius: 10)
            } else if mode == .drawer {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 100, height: 180)
                    .offset(x: 55)
            }
        }
    }
}

struct MorphingCard: View {
    let index: Int
    let mode: ViewMode
    
    let gradients: [[Color]] = [
        [Color(red: 0.30, green: 0.36, blue: 0.82), Color(red: 0.48, green: 0.38, blue: 0.90)],
        [Color(red: 0.18, green: 0.62, blue: 0.42), Color(red: 0.24, green: 0.72, blue: 0.52)],
        [Color(red: 0.82, green: 0.26, blue: 0.38), Color(red: 0.90, green: 0.34, blue: 0.44)],
        [Color(red: 0.30, green: 0.36, blue: 0.82), Color(red: 0.48, green: 0.38, blue: 0.90)],
        [Color(red: 0.88, green: 0.48, blue: 0.18), Color(red: 0.94, green: 0.56, blue: 0.24)],
        [Color(red: 0.63, green: 0.31, blue: 0.78), Color(red: 0.71, green: 0.39, blue: 0.86)]
    ]
    
    var body: some View {
        let isDrawer = mode == .drawer
        
        VStack(spacing: 0) {
            LinearGradient(colors: gradients[index % gradients.count], startPoint: .leading, endPoint: .trailing)
                .frame(height: isDrawer ? 20 : 8)
                .frame(width: isDrawer ? 4 : nil)
            
            if !isDrawer {
                Color(white: 0.15)
            } else {
                Color(white: 0.15)
                    .overlay(
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1)).frame(width: 30, height: 2)
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1)).frame(width: 20, height: 2)
                        }.padding(.leading, 6),
                        alignment: .leading
                    )
            }
        }
        .frame(width: width(for: mode), height: height(for: mode))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(mode == .tray && index == 2 ? 0.6 : 0.3), radius: mode == .tray && index == 2 ? 10 : 3)
        .overlay(
            mode == .tray && index == 2
                ? RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.90, green: 0.34, blue: 0.44), lineWidth: 1.5)
                : nil
        )
        .offset(offset(for: mode))
        // Rotate items slightly in radial mode
        .opacity(opacity(for: mode))
        .zIndex(zIndex(for: mode))
    }
    
    func width(for mode: ViewMode) -> CGFloat {
        switch mode {
        case .tray: return 32
        case .grid: return 45
        case .drawer: return 80
        case .panel: return 70
        case .radial: return 30
        case .workspace: return 54
        }
    }

    func height(for mode: ViewMode) -> CGFloat {
        switch mode {
        case .tray: return 40
        case .grid: return 35
        case .drawer: return 20
        case .panel: return 22
        case .radial: return 24
        case .workspace: return 30
        }
    }

    func offset(for mode: ViewMode) -> CGSize {
        switch mode {
        case .tray:
            let startX: CGFloat = -80
            let spacing: CGFloat = 40
            return CGSize(width: startX + CGFloat(index) * spacing, height: index == 2 ? 15 : 25)
        case .grid:
            let col = index % 3
            let row = index / 3
            return CGSize(width: -52 + CGFloat(col) * 52, height: -22 + CGFloat(row) * 44)
        case .drawer:
            return CGSize(width: 60, height: -50 + CGFloat(index) * 25)
        case .panel:
            return CGSize(width: 0, height: -54 + CGFloat(index) * 27)
        case .radial:
            let angle = Double(index) * (2 * .pi / 6) - (.pi / 2)
            let r: CGFloat = 40
            return CGSize(width: r * cos(angle), height: r * sin(angle))
        case .workspace:
            let col = index % 3
            let row = index / 3
            return CGSize(width: -52 + CGFloat(col) * 52, height: -18 + CGFloat(row) * 36)
        }
    }

    func opacity(for mode: ViewMode) -> Double {
        if mode == .tray && index >= 5 { return 0 }
        if mode == .drawer && index >= 5 { return 0 }
        if mode == .panel && index >= 5 { return 0 }
        return 1
    }
    
    func zIndex(for mode: ViewMode) -> Double {
        if mode == .tray && index == 2 { return 10 }
        return Double(index)
    }
}

// MARK: - Instant Action Animation
struct InstantActionAnimation: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = 3.0
            let progress = t.truncatingRemainder(dividingBy: cycle) / cycle
            
            let cursorX: CGFloat = progress < 0.3 ? 40 - CGFloat(progress / 0.3) * 40 :
                                   progress < 0.7 ? 0 :
                                   -CGFloat((progress - 0.7) / 0.3) * 40
            let cursorY: CGFloat = progress < 0.3 ? 40 - CGFloat(progress / 0.3) * 40 :
                                   progress < 0.7 ? 0 :
                                   CGFloat((progress - 0.7) / 0.3) * 40
                                   
            let isClick1 = progress >= 0.35 && progress < 0.4
            let isClick2 = progress >= 0.45 && progress < 0.5
            let cardScale: CGFloat = isClick1 || isClick2 ? 0.9 : 1.0
            let cursorScale: CGFloat = isClick1 || isClick2 ? 0.8 : 1.0

            let rippleOpac: Double = progress >= 0.5 && progress < 0.7 ? 1.0 - (progress - 0.5) / 0.2 : 0
            let rippleScale: CGFloat = progress >= 0.5 && progress < 0.7 ? 1.0 + CGFloat((progress - 0.5) / 0.2) * 1.5 : 0.5
            
            let accent = Color(red: 0.3, green: 0.78, blue: 0.55)
            
            ZStack {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.62, blue: 0.42), Color(red: 0.24, green: 0.72, blue: 0.52)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                        .frame(height: 12)
                    Color(white: 0.15)
                }
                .frame(width: 80, height: 50)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .scaleEffect(cardScale)
                .shadow(color: accent.opacity(isClick1 || isClick2 || rippleOpac > 0 ? 0.6 : 0), radius: isClick1 || isClick2 ? 5 : 20)
                
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent, lineWidth: 2)
                    .frame(width: 80, height: 50)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpac)

                Image(systemName: "cursorarrow")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .scaleEffect(cursorScale)
                    .offset(x: 6 + cursorX, y: 12 + cursorY)
            }
        }
    }
}
