import AppKit
import Carbon.HIToolbox
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var accessibilityPollTask: Task<Void, Never>?
    @State private var introFadeProgress = 0.0
    @State private var welcomePhase = 0

    private let totalSteps = 6
    
    // The onboarding window is pinned to 1060x720 by AppWindowManager.presentOnboarding,
    // so these are fixed constants — a "compact" variant can never occur.
    private struct OnboardingLayout {
        let windowWidth: CGFloat

        let horizontalPadding: CGFloat = 48
        let sectionPadding: CGFloat = 48
        let howItWorksSpacing: CGFloat = 24
        let permissionInset: CGFloat = 160
        let tabHorizontalPadding: CGFloat = 18
        let tabFontSize: CGFloat = 14
        let footerVerticalPadding: CGFloat = 22
        let primaryButtonMinWidth: CGFloat = 190
        let setupShortcutWidth: CGFloat = 180
        let stylePreviewMaxWidth: CGFloat = 900
    }

    static func introContentOpacity(for progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func introFocusOverlayOpacity(for progress: Double) -> Double {
        (1 - introContentOpacity(for: progress)) * 0.45
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { store.settings.appLanguage },
            set: { store.setAppLanguage($0) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let layout = OnboardingLayout(windowWidth: geo.size.width)
            
            ZStack {
                // Background
                BackgroundGlow(isWelcomeStep: currentStep == 0)

                // Content layer — padded to sit between header and footer
                ZStack {
                    switch currentStep {
                    case 0:
                        welcomeStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    case 1:
                        howItWorksStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    case 2:
                        permissionsStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    case 3:
                        setupStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    case 4:
                        styleStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    default:
                        readyStep(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.top, 56)
                .padding(.bottom, 80)
            }
            // Fill entire borderless window, then clip content overflow
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Per-screen wallpaper as background — won't expand the ZStack layout
            .background { wallpaperLayer }
            // Header — overlay anchored to the full window frame
            .overlay(alignment: .top) {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(Array(tabTitles.enumerated()), id: \.offset) { index, title in
                            Button {
                                if index <= currentStep { withAnimation(.easeInOut(duration: 0.3)) { currentStep = index } }
                            } label: {
                                Text(title)
                                    .font(.system(size: layout.tabFontSize, weight: .medium))
                                    .foregroundStyle(
                                        index == currentStep
                                            ? .white
                                            : index <= currentStep
                                                ? .white.opacity(0.6)
                                                : .white.opacity(0.2)
                                    )
                                    .padding(.horizontal, layout.tabHorizontalPadding)
                                    .padding(.vertical, 6)
                                    .background {
                                        if index == currentStep {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(.white.opacity(0.1))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 0)
                }
                .padding(.top, 20)
                .padding(.horizontal, layout.horizontalPadding)
                .transaction { $0.animation = nil }
            }
            // Footer — overlay isolates it completely from content transitions
            .overlay(alignment: .bottom) {
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<totalSteps, id: \.self) { i in
                            Capsule()
                                .fill(i == currentStep ? Color(red: 0.83, green: 0.66, blue: 0.26) : Color.white.opacity(0.15))
                                .frame(width: i == currentStep ? 18 : 6, height: 6)
                                .animation(.easeInOut(duration: 0.3), value: currentStep)
                        }
                    }
                    
                    Spacer()

                    HStack(spacing: 12) {
                        Button(L10n.string("ui.back", default: "Back")) {
                            withAnimation(.easeInOut(duration: 0.3)) { currentStep -= 1 }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(minWidth: 48)
                        .opacity(currentStep > 0 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: currentStep > 0)
                        .allowsHitTesting(currentStep > 0)

                        Button {
                            if currentStep == totalSteps - 1 {
                                finishOnboarding()
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) { currentStep += 1 }
                            }
                        } label: {
                            Text(primaryActionTitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(minWidth: layout.primaryButtonMinWidth)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.96, green: 0.82, blue: 0.48), Color(red: 0.83, green: 0.66, blue: 0.26)],
                                            startPoint: .top, endPoint: .bottom
                                        ))
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(currentStep == totalSteps - 1 && !accessibilityGranted)
                        .opacity(currentStep == totalSteps - 1 && !accessibilityGranted ? 0.55 : 1)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.footerVerticalPadding)
                .background(.black.opacity(0.2))
                .transaction { $0.animation = nil }
            }
            .background(Color(white: 0.08))
            .overlay {
                Color.black
                    .opacity(Self.introFocusOverlayOpacity(for: introFadeProgress))
                    .allowsHitTesting(false)
            }
            .opacity(Self.introContentOpacity(for: introFadeProgress))
            .preferredColorScheme(.dark)
            .onAppear {
                accessibilityGranted = AccessibilityService.isTrusted()
                introFadeProgress = 0
                withAnimation(.easeOut(duration: 3.0)) {
                    introFadeProgress = 1
                }
            }
            .onDisappear {
                accessibilityPollTask?.cancel()
                accessibilityPollTask = nil
            }
            .onChange(of: currentStep) { oldStep, newStep in
                // Hide mode preview when leaving the style step
                if oldStep == 4 {
                    AppWindowManager.shared.hideOnboardingPreview()
                }
                // Remove blur + lower window on permissions step so users can reach System Settings
                if newStep == 2 {
                    AppWindowManager.shared.setTheaterBlurHidden(true)
                } else if oldStep == 2 {
                    AppWindowManager.shared.setTheaterBlurHidden(false)
                }
            }
        }
    }

    private struct BackgroundGlow: View {
        let isWelcomeStep: Bool

        var body: some View {
            ZStack {
                if isWelcomeStep {
                    OnboardingAuroraLayer()
                        .transition(.opacity)
                }

                Circle()
                    .fill(Color(red: 0.4, green: 0.52, blue: 0.96).opacity(0.15))
                    .frame(width: 600)
                    .blur(radius: 80)
                    .offset(x: -300, y: -250)
                
                Circle()
                    .fill(Color(red: 0.83, green: 0.66, blue: 0.26).opacity(0.1))
                    .frame(width: 600)
                    .blur(radius: 80)
                    .offset(x: 300, y: 250)
            }
            .allowsHitTesting(false)
        }
    }

    private var tabTitles: [String] {
        OnboardingCopy.tabTitles()
    }

    private var primaryActionTitle: String {
        OnboardingCopy.primaryActionTitle(
            isLastStep: currentStep == totalSteps - 1,
            accessibilityGranted: accessibilityGranted
        )
    }

    // MARK: - Step 1: Welcome

    private func welcomeStep(layout: OnboardingLayout) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Keep the wordmark lowercase here because the intro animation is designed
            // around a single compact word rather than title case.
            Text(AppBrand.displayName.lowercased())
                .font(.system(size: 120, weight: .thin))
                .tracking(-4)
                .foregroundStyle(.white)
                .opacity(welcomePhase >= 1 ? 1 : 0)

            // Tagline
            Text(OnboardingCopy.welcomeTagline())
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .opacity(welcomePhase >= 2 ? 1 : 0)
                .padding(.top, 4)

            // Feature hints
            VStack(spacing: 14) {
                Text(OnboardingCopy.welcomeHints()[0])
                    .opacity(welcomePhase >= 3 ? 1 : 0)
                Text(OnboardingCopy.welcomeHints()[1])
                    .opacity(welcomePhase >= 4 ? 1 : 0)
                Text(OnboardingCopy.welcomeHints()[2])
                    .opacity(welcomePhase >= 5 ? 1 : 0)
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.top, 32)

            VStack(spacing: 8) {
                Text(OnboardingCopy.languageTitle())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Picker(OnboardingCopy.languageTitle(), selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(OnboardingCopy.languageTitle())
                .frame(width: min(max(layout.windowWidth * 0.34, 220), 320))

                Text(OnboardingCopy.languageSubtitle())
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.top, 28)

            Spacer()
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) { welcomePhase = 1 }
            withAnimation(.easeOut(duration: 0.7).delay(0.9)) { welcomePhase = 2 }
            withAnimation(.easeOut(duration: 0.5).delay(1.5)) { welcomePhase = 3 }
            withAnimation(.easeOut(duration: 0.5).delay(1.9)) { welcomePhase = 4 }
            withAnimation(.easeOut(duration: 0.5).delay(2.3)) { welcomePhase = 5 }
        }
    }

    // MARK: - Step 2: How It Works

    private func howItWorksStep(layout: OnboardingLayout) -> some View {
        let cards = OnboardingCopy.howItWorksCards()

        return VStack(alignment: .leading, spacing: 0) {
            Text(OnboardingCopy.howItWorksTitle())
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
            Text(OnboardingCopy.howItWorksSubtitle())
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)

            HStack(spacing: layout.howItWorksSpacing) {
                let accent = SettingsTheme.primaryAccent

                howItWorksCard(
                    number: cards[0].number,
                    title: cards[0].title,
                    description: cards[0].description,
                    color: accent
                ) {
                    DataFlowCaptureAnimation()
                }

                howItWorksCard(
                    number: cards[1].number,
                    title: cards[1].title,
                    description: cards[1].description,
                    color: accent
                ) {
                    VisualHistoryAnimation()
                }

                howItWorksCard(
                    number: cards[2].number,
                    title: cards[2].title,
                    description: cards[2].description,
                    color: accent
                ) {
                    InstantActionAnimation()
                }
            }
            .padding(.top, 24)

            Spacer()
        }
        .padding(layout.sectionPadding)
    }

    private func howItWorksCard<Content: View>(
        number: String,
        title: String,
        description: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .tracking(1)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.44))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.20), lineWidth: 1)
                    )

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 140, maxHeight: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(colors: [color.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    .white.opacity(0.10),
                    lineWidth: 0.8
                )
        )
    }

    // MARK: - Step 3: Permissions

    private func permissionsStep(layout: OnboardingLayout) -> some View {
        let accent = SettingsTheme.primaryAccent

        return VStack(spacing: 0) {
            Spacer()

            // Shield icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.12), .clear],
                            center: .center, startRadius: 15, endRadius: 50
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            .padding(.bottom, 12)

            Text(OnboardingCopy.permissionsTitle())
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)

            Text(OnboardingCopy.permissionsSubtitle())
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 3)
                .padding(.bottom, 20)

            // Two permission tiles side by side
            HStack(spacing: 14) {
                permissionTile(
                    icon: "doc.on.clipboard",
                    title: OnboardingCopy.clipboardPermissionTitle(),
                    subtitle: OnboardingCopy.clipboardPermissionSubtitle(),
                    granted: true,
                    accentColor: Color(red: 0.4, green: 0.52, blue: 0.96)
                )

                permissionTile(
                    icon: "hand.tap",
                    title: OnboardingCopy.accessibilityPermissionTitle(),
                    subtitle: OnboardingCopy.accessibilityPermissionSubtitle(),
                    granted: accessibilityGranted,
                    accentColor: Color(red: 0.3, green: 0.78, blue: 0.55),
                    action: accessibilityGranted ? nil : {
                        store.requestAccessibilityPermission()
                        store.openAccessibilitySettings()
                        accessibilityPollTask?.cancel()
                        accessibilityPollTask = Task {
                            for _ in 0..<40 {
                                guard !Task.isCancelled else { return }
                                try? await Task.sleep(for: .milliseconds(500))
                                let granted = AccessibilityService.isTrusted()
                                if granted {
                                    await MainActor.run {
                                        withAnimation(.spring()) {
                                            accessibilityGranted = true
                                        }
                                        accessibilityPollTask = nil
                                    }
                                    break
                                }
                            }
                        }
                    }
                )
            }
            .padding(.horizontal, layout.permissionInset)

            Spacer()
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    private func permissionTile(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        accentColor: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        let accent = SettingsTheme.primaryAccent

        return VStack(spacing: 10) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(granted ? accentColor.opacity(0.20) : .black.opacity(0.35))
                    .frame(width: 44, height: 44)

                Image(systemName: granted ? "checkmark" : icon)
                    .font(.system(size: 20, weight: granted ? .bold : .medium))
                    .foregroundStyle(granted ? accentColor : .white.opacity(0.62))
            }

            Text(title)
                .font(.system(size: 15, weight: .bold))

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)

            // Status / action
            if granted {
                Text(OnboardingCopy.permissionActiveLabel())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12), in: Capsule())
            } else if let action {
                Button(action: action) {
                    Text(OnboardingCopy.permissionEnableLabel())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.42))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    granted ? accentColor.opacity(0.38) : .white.opacity(0.14),
                    lineWidth: 1.1
                )
        )
    }

    // MARK: - Step 4: Quick Setup

    @State private var setupRowsAppeared = false

    private func setupStep(layout: OnboardingLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(OnboardingCopy.setupTitle())
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                Text(OnboardingCopy.setupSubtitle())
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            let bentoSpacing: CGFloat = 12

            VStack(spacing: bentoSpacing) {
                // Top row — Launch at Login + History Duration
                HStack(spacing: bentoSpacing) {
                    // Launch at Login — entire card is a toggle
                    launchAtLoginCard(index: 0)

                    // History Duration
                    historyDurationCard(index: 1)
                }

                // Global Hotkey — full width
                bentoCard(
                    icon: "keyboard",
                    accentStart: Color(red: 0.65, green: 0.40, blue: 0.95),
                    accentEnd: Color(red: 0.50, green: 0.25, blue: 0.85),
                    title: OnboardingCopy.globalHotkeyTitle(),
                    subtitle: OnboardingCopy.globalHotkeySubtitle(),
                    index: 2
                ) {
                    Spacer()
                    ShortcutRecorderField(shortcut: globalShortcutBinding) { captured in
                        store.setGlobalShortcut(captured)
                    }
                    .frame(width: layout.setupShortcutWidth, height: 28)
                }

                if let error = store.globalShortcutError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
            .padding(.top, 28)

            Spacer()
        }
        .padding(layout.sectionPadding)
        .onAppear { setupRowsAppeared = false; withAnimation(.easeOut(duration: 0.5).delay(0.15)) { setupRowsAppeared = true } }
        .onDisappear { setupRowsAppeared = false }
    }

    /// Launch at Login — the entire card is a big tappable toggle.
    private func launchAtLoginCard(index: Int) -> some View {
        let isOn = store.settings.launchAtLogin
        let accent = Color(red: 0.95, green: 0.65, blue: 0.20)

        return Button {
            let newValue = !isOn
            withAnimation(.easeInOut(duration: 0.25)) {
                store.settings.launchAtLogin = newValue
            }
            Task { @MainActor in store.setLaunchAtLogin(newValue) }
        } label: {
            VStack(spacing: 0) {
                // Top: icon + text
                HStack(spacing: 10) {
                    bentoIcon(
                        icon: "sunrise",
                        accentStart: Color(red: 0.95, green: 0.65, blue: 0.20),
                        accentEnd: Color(red: 0.88, green: 0.45, blue: 0.12)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(OnboardingCopy.launchAtLoginTitle())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(OnboardingCopy.launchAtLoginSubtitle())
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                Spacer(minLength: 16)

                // Big status indicator centered
                HStack(spacing: 10) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isOn ? accent : .white.opacity(0.25))

                    Text(isOn ? OnboardingCopy.enabledStatus() : OnboardingCopy.disabledStatus())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOn ? .white.opacity(0.95) : .white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isOn ? accent.opacity(0.15) : .white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isOn ? accent.opacity(0.3) : .white.opacity(0.06), lineWidth: 0.5)
                )

                if let error = store.launchAtLoginError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.top, 1)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                    if isOn {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                RadialGradient(
                                    colors: [accent.opacity(0.08), .clear],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 200
                                )
                            )
                    }
                    VStack {
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 1)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isOn ? accent.opacity(0.25) : .white.opacity(0.06), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(setupRowsAppeared ? 1 : 0)
        .offset(y: setupRowsAppeared ? 0 : 14)
        .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.12 + 0.1), value: setupRowsAppeared)
    }

    /// History Duration — vertical stack of large selectable options.
    private func historyDurationCard(index: Int) -> some View {
        let blueAccent = Color(red: 0.35, green: 0.60, blue: 0.95)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                bentoIcon(
                    icon: "clock.arrow.circlepath",
                    accentStart: Color(red: 0.35, green: 0.60, blue: 0.95),
                    accentEnd: Color(red: 0.22, green: 0.42, blue: 0.85)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(OnboardingCopy.historyDurationTitle())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(OnboardingCopy.historyDurationSubtitle())
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 5) {
                ForEach(HistoryRetention.allCases, id: \.self) { r in
                    let isSelected = store.settings.historyRetention == r
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.setRetention(r)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(isSelected ? blueAccent : .white.opacity(0.20))

                            Text(r.label)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? blueAccent.opacity(0.18) : .white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? blueAccent.opacity(0.3) : .clear, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                VStack {
                    LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 1)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            }
        }
        .opacity(setupRowsAppeared ? 1 : 0)
        .offset(y: setupRowsAppeared ? 0 : 14)
        .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.12 + 0.1), value: setupRowsAppeared)
    }

    /// Bento card used for the Global Hotkey row.
    /// Horizontal layout: icon + text left, control right.
    @ViewBuilder
    private func bentoCard<Control: View>(
        icon: String,
        accentStart: Color,
        accentEnd: Color,
        title: String,
        subtitle: String,
        index: Int,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            bentoIcon(icon: icon, accentStart: accentStart, accentEnd: accentEnd)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }

            control()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // Solid dark background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))

                // Subtle accent glow
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [accentStart.opacity(0.06), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )

                // Top highlight
                VStack {
                    LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 1)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                    Spacer()
                }

                // Border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            }
        }
        .opacity(setupRowsAppeared ? 1 : 0)
        .offset(y: setupRowsAppeared ? 0 : 14)
        .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.12 + 0.1), value: setupRowsAppeared)
    }

    private func bentoIcon(icon: String, accentStart: Color, accentEnd: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [accentStart, accentEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: accentEnd.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Step 5: Choose Your Style

    private func styleStep(layout: OnboardingLayout) -> some View {
        VStack(spacing: 0) {
            // Centered header
            VStack(spacing: 4) {
                Text(OnboardingCopy.styleTitle())
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                Text(OnboardingCopy.styleSubtitle())
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            // Horizontal mode selector pills
            HStack(spacing: 8) {
                ForEach(ViewMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.settings.viewMode = mode
                        }
                        AppWindowManager.shared.previewModeForOnboarding(mode: mode, store: store)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 15))
                            Text(mode.label)
                                .font(.system(size: 12, weight: store.settings.viewMode == mode ? .bold : .medium))
                        }
                        .foregroundStyle(store.settings.viewMode == mode ? .white : .white.opacity(0.80))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(store.settings.viewMode == mode
                                      ? .black.opacity(0.56)
                                      : .black.opacity(0.42))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    store.settings.viewMode == mode
                                        ? Color(red: 0.83, green: 0.66, blue: 0.26).opacity(0.92)
                                        : .white.opacity(0.16),
                                    lineWidth: 1.1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            // Live video preview — aspect ratio matched to videos (~1.61:1)
            OnboardingVideoPreview(mode: store.settings.viewMode)
                .aspectRatio(3480.0 / 2160.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .frame(maxWidth: layout.stylePreviewMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: store.settings.viewMode)

            // Mode description
            Text(OnboardingCopy.modeDescription(for: store.settings.viewMode))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .animation(.easeInOut(duration: 0.2), value: store.settings.viewMode)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Step 6: Ready

    private func readyStep(layout: OnboardingLayout) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(red: 0.83, green: 0.66, blue: 0.26).opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(1.1)
                    .opacity(0.35)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.94, green: 0.85, blue: 0.48), Color(red: 0.77, green: 0.60, blue: 0.22)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .shadow(color: Color(red: 0.83, green: 0.66, blue: 0.26).opacity(0.4), radius: 20, y: 10)
            }
            .padding(.bottom, 32)

            Text(OnboardingCopy.readyTitle())
                .font(.system(size: 32, weight: .bold))
                .tracking(-1)

            Text(OnboardingCopy.readySubtitle())
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            if !accessibilityGranted {
                Text(OnboardingCopy.readyAccessibilityWarning())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.96, green: 0.82, blue: 0.48))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }

            // Hotkey reminder
            HStack(spacing: 12) {
                Text(OnboardingCopy.toggleShelfLabel())
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                
                HStack(spacing: 6) {
                    ForEach(shortcutKeyCaps, id: \.self) { cap in
                        keyCap(cap)
                    }
                }
            }
            .padding(.top, 40)

            Spacer()
        }
        .padding(layout.sectionPadding)
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    private var globalShortcutBinding: Binding<GlobalShortcut> {
        Binding(
            get: { store.settings.globalShortcut },
            set: { store.setGlobalShortcut($0) }
        )
    }

    private var shortcutKeyCaps: [String] {
        let shortcut = store.settings.globalShortcut
        var caps: [String] = []

        if shortcut.modifiers & UInt32(cmdKey) != 0 { caps.append("⌘") }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { caps.append("⇧") }
        if shortcut.modifiers & UInt32(optionKey) != 0 { caps.append("⌥") }
        if shortcut.modifiers & UInt32(controlKey) != 0 { caps.append("⌃") }

        caps.append(GlobalShortcut.displayName(for: shortcut.keyCode))
        return caps
    }

    // MARK: - Wallpaper Background

    private static let wallpaperNames = ["terra", "terra-pyramid", "terra-lagoon", "terra-rivers", "terra-bloom", "terra-aurora"]

    @ViewBuilder
    private var wallpaperLayer: some View {
        let name = Self.wallpaperNames[currentStep]

        if let url = AppResourceLocator.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
           let nsImage = NSImage(contentsOf: url) {
            GeometryReader { geo in
                ZStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.7)

                    // Top fade for header readability
                    LinearGradient(
                        stops: [
                            .init(color: Color(white: 0.08, opacity: 0.5), location: 0),
                            .init(color: .clear, location: 0.18),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )

                    // Bottom fade for footer + content readability
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4),
                            .init(color: Color(white: 0.08, opacity: 0.7), location: 0.7),
                            .init(color: Color(white: 0.08, opacity: 0.95), location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )

                    // Subtle radial vignette
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.1),
                            .init(color: Color(white: 0.08, opacity: 0.4), location: 0.7),
                        ]),
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 100,
                        endRadius: 500
                    )
                }
            }
            .id("wallpaper-\(currentStep)")
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func finishOnboarding() {
        guard accessibilityGranted else {
            store.requestAccessibilityPermission()
            store.openAccessibilitySettings()
            return
        }
        accessibilityPollTask?.cancel()
        accessibilityPollTask = nil

        if let keyWindow = NSApp.keyWindow {
            keyWindow.makeFirstResponder(nil)
        }

        store.completeOnboarding()
        AppWindowManager.shared.dismissOnboarding()
    }
}
