import Foundation

nonisolated protocol VisionLinkServerServing:
    Sendable
{
    func createReceiverSession(
        deviceName: String
    ) async throws -> VisionLinkSessionResponse

    func reconnectReceiver(
        credentials: VisionLinkStoredCredentials,
        deviceName: String
    ) async throws -> VisionLinkReconnectResponse

    func deleteReceiverPair(
        credentials: VisionLinkStoredCredentials
    ) async throws
}

nonisolated final class VisionLinkServerClient:
    VisionLinkServerServing,
    @unchecked Sendable
{
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = VisionLinkContract.baseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func createReceiverSession(
        deviceName: String
    ) async throws -> VisionLinkSessionResponse {
        let request = try makeRequest(
            pathComponents: ["sessions"],
            payload: [
                "receiverName": normalizedDeviceName(
                    deviceName
                )
            ]
        )
        let data = try await execute(request)
        return try VisionLinkJSON.decodeSession(data)
    }

    func reconnectReceiver(
        credentials: VisionLinkStoredCredentials,
        deviceName: String
    ) async throws -> VisionLinkReconnectResponse {
        let request = try makeRequest(
            pathComponents: [
                "pairs",
                credentials.pairID,
                "connect"
            ],
            payload: [
                "role": VisionLinkContract.receiverRole,
                "deviceId": credentials.deviceID,
                "deviceToken": credentials.deviceToken,
                "deviceName": normalizedDeviceName(
                    deviceName
                )
            ]
        )
        let data = try await execute(request)
        return try VisionLinkJSON.decodeReconnect(data)
    }

    func deleteReceiverPair(
        credentials: VisionLinkStoredCredentials
    ) async throws {
        let request = try makeRequest(
            pathComponents: [
                "pairs",
                credentials.pairID,
                "delete"
            ],
            payload: [
                "role": VisionLinkContract.receiverRole,
                "deviceId": credentials.deviceID,
                "deviceToken": credentials.deviceToken
            ]
        )
        _ = try await execute(request)
    }

    private func makeRequest(
        pathComponents: [String],
        payload: [String: Any]
    ) throws -> URLRequest {
        let url = pathComponents.reduce(baseURL) {
            partialURL,
            component in
            partialURL.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue(
            "application/json; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )
        return request
    }

    private func execute(
        _ request: URLRequest
    ) async throws -> Data {
        let (data, response) = try await session.data(
            for: request
        )
        guard let response = response as? HTTPURLResponse else {
            throw VisionLinkServerError.invalidResponse
        }
        guard (200 ... 299).contains(
            response.statusCode
        ) else {
            throw VisionLinkServerError.http(
                statusCode: response.statusCode,
                responseBody: String(
                    data: data.prefix(320),
                    encoding: .utf8
                ) ?? ""
            )
        }
        return data
    }

    private func normalizedDeviceName(
        _ value: String
    ) -> String {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return String(
            (normalized.isEmpty ? "RivoPad" : normalized)
                .prefix(80)
        )
    }
}

nonisolated enum VisionLinkServerError:
    Error,
    LocalizedError,
    Equatable
{
    case invalidResponse
    case http(statusCode: Int, responseBody: String)

    var statusCode: Int? {
        if case .http(let statusCode, _) = self {
            return statusCode
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "VisionLink 서버 응답을 확인할 수 없습니다."
        case .http(let statusCode, let responseBody):
            let detail = responseBody.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if detail.isEmpty {
                return "VisionLink 서버 오류 \(statusCode)"
            }
            return "VisionLink 서버 오류 \(statusCode): "
                + String(detail.prefix(160))
        }
    }
}
