import Foundation

extension ClipboardStore {
    // MARK: - Licensing & Trial

    /// Computed aggregate access state — use this to gate UI.
    var appAccessState: AppAccessState {
        if licenseState.isLicensed { return .fullAccess }
        switch trialState {
        case .active(let remaining): return .trialActive(remaining: remaining)
        case .expired, .notStarted: return .locked
        }
    }

    nonisolated static func resolveTrialStartStorage(
        keychainTrialStartedAt: String?,
        legacySettingsTrialStartedAt: String?
    ) -> TrialStartStorageResolution {
        if let keychainTrialStartedAt {
            return TrialStartStorageResolution(
                effectiveTrialStartedAt: keychainTrialStartedAt,
                shouldPersistToKeychain: false,
                shouldClearLegacySettingsValue: legacySettingsTrialStartedAt != nil
            )
        }

        if let legacySettingsTrialStartedAt {
            return TrialStartStorageResolution(
                effectiveTrialStartedAt: legacySettingsTrialStartedAt,
                shouldPersistToKeychain: true,
                shouldClearLegacySettingsValue: true
            )
        }

        return TrialStartStorageResolution(
            effectiveTrialStartedAt: nil,
            shouldPersistToKeychain: false,
            shouldClearLegacySettingsValue: false
        )
    }

    nonisolated static func trialState(
        licenseState: LicenseState,
        trialStartedAt: String?,
        now: Date,
        trialDurationHours: Double = PolarConstants.trialDurationHours
    ) -> TrialState {
        guard !licenseState.isLicensed else {
            return .active(remaining: .infinity)
        }

        guard let trialStartedAt,
              let startDate = ISO8601DateFormatter().date(from: trialStartedAt)
        else {
            return .notStarted
        }

        let elapsed = now.timeIntervalSince(startDate)
        let remaining = (trialDurationHours * 3600) - elapsed
        return remaining > 0 ? .active(remaining: remaining) : .expired
    }

    func bootstrapLicenseState() {
        migrateLegacyTrialStartDateIfNeeded()

        if let key = LicenseVault.licenseKey, let actID = LicenseVault.activationID {
            licenseState = .licensed(activationID: actID)
            trialState = .active(remaining: .infinity)
            Task { await refreshLicenseStatus(key: key, activationID: actID) }
        } else {
            licenseState = .unlicensed
            beginTrialIfNeeded()
        }
        startTrialRefreshTimer()
    }

    private func migrateLegacyTrialStartDateIfNeeded() {
        let resolution = Self.resolveTrialStartStorage(
            keychainTrialStartedAt: LicenseVault.trialStartedAt,
            legacySettingsTrialStartedAt: settings.trialStartedAt
        )

        if resolution.shouldPersistToKeychain, let effectiveTrialStartedAt = resolution.effectiveTrialStartedAt {
            LicenseVault.trialStartedAt = effectiveTrialStartedAt
            logState("Migrated trial start date from UserDefaults to Keychain")
        }

        if resolution.shouldClearLegacySettingsValue, settings.trialStartedAt != nil {
            settings.trialStartedAt = nil
        }
    }

    /// Start the 24-hour trial clock if it hasn't started yet.
    func beginTrialIfNeeded() {
        if LicenseVault.trialStartedAt == nil {
            let now = ISO8601DateFormatter().string(from: Date())
            LicenseVault.trialStartedAt = now
            logState("Trial started at \(now)")
            Analytics.trialStarted()
        }
        evaluateTrialState()
    }

    /// Recalculate trial state from persisted timestamp, and sync clipboard monitor.
    func evaluateTrialState() {
        trialState = Self.trialState(
            licenseState: licenseState,
            trialStartedAt: LicenseVault.trialStartedAt ?? settings.trialStartedAt,
            now: Date()
        )
        syncMonitorWithAccessState()
    }

    /// Stop clipboard monitoring when locked so the app does not capture data after access expires.
    private func syncMonitorWithAccessState() {
        if appAccessState == .locked {
            monitor.stop()
            logState("Monitor paused — app is locked")
        } else {
            monitor.start()
        }
    }

    /// Periodically refresh trial countdown (every 60 seconds).
    private func startTrialRefreshTimer() {
        trialRefreshTimer?.invalidate()
        trialRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTrialState()
            }
        }
    }

    func refreshLicenseStatus(key: String? = nil, activationID: String? = nil) async {
        let licenseKey = key ?? LicenseVault.licenseKey
        let actID = activationID ?? LicenseVault.activationID

        guard let licenseKey, let actID else {
            licenseState = .unlicensed
            evaluateTrialState()
            return
        }

        do {
            let valid = try await PolarLicenseService.shared.validate(key: licenseKey, activationID: actID)
            if valid {
                licenseState = .licensed(activationID: actID)
            } else {
                LicenseVault.clearAll()
                licenseState = .unlicensed
                evaluateTrialState()
            }
        } catch {
            logState("License validation failed (offline?): \(error.localizedDescription)")
        }
    }

    func activateLicenseKey(_ key: String) async {
        isLicenseBusy = true
        licenseErrorMessage = nil

        do {
            let activationID = try await PolarLicenseService.shared.activate(key: key)
            LicenseVault.licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            LicenseVault.activationID = activationID
            licenseState = .licensed(activationID: activationID)
            trialState = .active(remaining: .infinity)
            logState("License activated successfully")
            Analytics.licenseActivated()
        } catch {
            licenseErrorMessage = error.localizedDescription
            logState("License activation error: \(error.localizedDescription)")
        }

        isLicenseBusy = false
    }

    func deactivateCurrentDevice() async {
        guard let key = LicenseVault.licenseKey, let actID = LicenseVault.activationID else {
            licenseErrorMessage = LicenseError.noActivationStored.localizedDescription
            return
        }

        isLicenseBusy = true
        licenseErrorMessage = nil

        do {
            try await PolarLicenseService.shared.deactivate(key: key, activationID: actID)
            LicenseVault.clearAll()
            licenseState = .unlicensed
            evaluateTrialState()
            logState("License deactivated")
        } catch {
            licenseErrorMessage = error.localizedDescription
            logState("License deactivation error: \(error.localizedDescription)")
        }

        isLicenseBusy = false
    }
}
