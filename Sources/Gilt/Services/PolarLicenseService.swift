import Foundation

/// Async client for Polar's public customer-portal license-key endpoints.
/// No secret tokens — safe to embed in a desktop app.
actor PolarLicenseService {
    static let shared = PolarLicenseService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    // MARK: - Activate

    /// Activate a license key on this Mac. Returns the activation ID on success.
    func activate(key: String) async throws -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LicenseError.invalidKey }

        let body = PolarActivateRequest(
            key: trimmedKey,
            organizationId: PolarConstants.organizationID,
            label: LicenseVault.machineLabel
        )

        let request = try buildRequest(path: "/activate", body: body)

        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError("Invalid response")
        }

        if http.statusCode == 200 || http.statusCode == 201 {
            let result = try decoder.decode(PolarActivateResponse.self, from: data)
            return result.id
        }

        // Parse error
        let apiError = try? decoder.decode(PolarErrorResponse.self, from: data)
        let message = apiError?.message ?? "HTTP \(http.statusCode)"

        if http.statusCode == 422 || message.lowercased().contains("limit") {
            throw LicenseError.activationLimitReached
        }
        throw LicenseError.activationFailed(message)
    }

    // MARK: - Validate

    /// Validate a license key + activation. Returns true if valid.
    func validate(key: String, activationID: String) async throws -> Bool {
        let body = PolarValidateRequest(
            key: key,
            organizationId: PolarConstants.organizationID,
            activationId: activationID,
            benefitId: PolarConstants.benefitID
        )

        let request = try buildRequest(path: "/validate", body: body)

        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError("Invalid response")
        }

        if http.statusCode == 200 {
            let result = try decoder.decode(PolarValidateResponse.self, from: data)
            return result.isValid
        }

        let apiError = try? decoder.decode(PolarErrorResponse.self, from: data)
        throw LicenseError.validationFailed(apiError?.message ?? "HTTP \(http.statusCode)")
    }

    // MARK: - Deactivate

    /// Deactivate this Mac's activation. Frees up one activation slot.
    func deactivate(key: String, activationID: String) async throws {
        let body = PolarDeactivateRequest(
            key: key,
            organizationId: PolarConstants.organizationID,
            activationId: activationID
        )

        let request = try buildRequest(path: "/deactivate", body: body)

        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError("Invalid response")
        }

        if http.statusCode == 200 || http.statusCode == 204 {
            return
        }

        let apiError = try? decoder.decode(PolarErrorResponse.self, from: data)
        throw LicenseError.deactivationFailed(apiError?.message ?? "HTTP \(http.statusCode)")
    }

    // MARK: - Helpers

    private func buildRequest<T: Encodable>(path: String, body: T) throws -> URLRequest {
        guard let url = URL(string: PolarConstants.baseURL + path) else {
            throw LicenseError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw LicenseError.networkError(error.localizedDescription)
        } catch {
            throw LicenseError.networkError(error.localizedDescription)
        }
    }
}
