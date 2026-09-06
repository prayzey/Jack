import Foundation

// MARK: - License State

enum LicenseState: Equatable {
    case unknown
    case licensed(activationID: String)
    case unlicensed
    case error(String)

    var isLicensed: Bool {
        if case .licensed = self { return true }
        return false
    }
}

// MARK: - Trial State

enum TrialState: Equatable {
    case active(remaining: TimeInterval)
    case expired
    case notStarted

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

}

// MARK: - Aggregate Access State

/// Combined license + trial evaluation for gating app features.
enum AppAccessState: Equatable {
    case fullAccess
    case trialActive(remaining: TimeInterval)
    case locked
}

// MARK: - Polar API Constants

enum PolarConstants {
    static let organizationID = "b3facce4-af41-4911-bdfb-76247af3fc5e"
    static let benefitID = "538175d2-1dfa-48a0-9d1f-425f76efe11c"
    static let checkoutURL = "https://buy.polar.sh/polar_cl_ljNz6PnPXuAFdxCenpCPCRDOAGL0GGnU3YSj02hvV6M"
    static let baseURL = "https://api.polar.sh/v1/customer-portal/license-keys"
    static let trialDurationHours: Double = 24
}

// MARK: - Polar API Request Bodies

struct PolarActivateRequest: Encodable {
    let key: String
    let organizationId: String
    let label: String

    enum CodingKeys: String, CodingKey {
        case key
        case organizationId = "organization_id"
        case label
    }
}

struct PolarValidateRequest: Encodable {
    let key: String
    let organizationId: String
    let activationId: String
    let benefitId: String

    enum CodingKeys: String, CodingKey {
        case key
        case organizationId = "organization_id"
        case activationId = "activation_id"
        case benefitId = "benefit_id"
    }
}

struct PolarDeactivateRequest: Encodable {
    let key: String
    let organizationId: String
    let activationId: String

    enum CodingKeys: String, CodingKey {
        case key
        case organizationId = "organization_id"
        case activationId = "activation_id"
    }
}

// MARK: - Polar API Response Bodies

struct PolarActivateResponse: Decodable {
    let id: String
    let licenseKeyId: String

    enum CodingKeys: String, CodingKey {
        case id
        case licenseKeyId = "license_key_id"
    }
}

struct PolarValidateResponse: Decodable {
    let id: String
    let organizationId: String
    let userId: String?
    let status: String
    let limitActivations: Int?
    let activations: Int?
    let validationTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case userId = "user_id"
        case status
        case limitActivations = "limit_activations"
        case activations
        case validationTimestamp = "validation_timestamp"
    }

    var isValid: Bool {
        status == "granted" || status == "active"
    }
}

struct PolarDeactivateResponse: Decodable {
    let id: String?
}

struct PolarErrorResponse: Decodable {
    let detail: String?
    let type: String?

    /// Friendly error message derived from the API response.
    var message: String {
        detail ?? "An unknown error occurred"
    }
}

// MARK: - License Service Errors

enum LicenseError: LocalizedError {
    case networkError(String)
    case activationFailed(String)
    case validationFailed(String)
    case deactivationFailed(String)
    case invalidKey
    case activationLimitReached
    case noActivationStored

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .activationFailed(let msg): return "Activation failed: \(msg)"
        case .validationFailed(let msg): return "Validation failed: \(msg)"
        case .deactivationFailed(let msg): return "Deactivation failed: \(msg)"
        case .invalidKey: return "Invalid license key"
        case .activationLimitReached: return "Activation limit reached (3 devices). Deactivate another device first."
        case .noActivationStored: return "No activation found on this device"
        }
    }
}
