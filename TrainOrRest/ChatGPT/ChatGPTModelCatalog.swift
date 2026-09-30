import Foundation

struct ChatGPTModel: Equatable, Identifiable, Hashable {
    /// The `slug` sent as `model`.
    let id: String
    let displayName: String
}

actor ChatGPTModelCatalog {
    static let shared = ChatGPTModelCatalog()

    private static let preferredModelIDs = ["gpt-5.5", "gpt-5.4", "gpt-5-mini"]

    private let session: URLSession
    private let defaults: UserDefaults
    private var cachedModels: [ChatGPTModel]?

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    /// Listed models for the signed-in account, cached per launch.
    func models(tokenProvider: ChatGPTTokenProviding, forceRefresh: Bool = false) async throws -> [ChatGPTModel] {
        if !forceRefresh, let cachedModels {
            return cachedModels
        }

        var token = try await tokenProvider.accessToken()
        var didRefreshAfterUnauthorized = false

        while true {
            do {
                let loadedModels = try await fetchModels(token: token)
                cachedModels = loadedModels
                return loadedModels
            } catch is ChatGPTModelCatalogUnauthorized {
                if didRefreshAfterUnauthorized {
                    let error = ClaudeClientError.needsReconnect
                    await tokenProvider.recordPlanError(error)
                    throw error
                }
                didRefreshAfterUnauthorized = true
                token = try await tokenProvider.refreshAfterUnauthorized()
            } catch let error as ClaudeClientError {
                if Self.recordsPlanError(error) {
                    await tokenProvider.recordPlanError(error)
                }
                throw error
            }
        }
    }

    /// Ensures `coachModel.chatGPT` names a listed model, writing the default when missing or delisted.
    func resolveSelectedModel(tokenProvider: ChatGPTTokenProviding) async throws -> String {
        let listedModels = try await models(tokenProvider: tokenProvider)
        guard let defaultModel = Self.defaultModel(from: listedModels) else {
            throw ClaudeClientError.api("No ChatGPT models are available for this account.")
        }

        let storageKey = CoachConnection.chatGPT.modelStorageKey
        if let selectedModel = defaults.string(forKey: storageKey),
           !selectedModel.isEmpty,
           listedModels.contains(where: { $0.id == selectedModel }) {
            return selectedModel
        }

        defaults.set(defaultModel, forKey: storageKey)
        return defaultModel
    }

    /// Drops the cached list, e.g. after the account changed.
    func invalidate() {
        cachedModels = nil
    }

    nonisolated static func defaultModel(from models: [ChatGPTModel]) -> String? {
        for preferredID in preferredModelIDs where models.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return models.first?.id
    }

    private func fetchModels(token: String) async throws -> [ChatGPTModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeClientError.invalidResponse
            }
            if http.statusCode == 401 {
                throw ChatGPTModelCatalogUnauthorized()
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(for: http.statusCode, data: data)
            }

            let decoded = try JSONDecoder().decode(ChatGPTModelsResponse.self, from: data)
            if let models = decoded.models {
                return models.compactMap { model in
                    guard model.visibility == "list" else { return nil }
                    return ChatGPTModel(id: model.slug, displayName: model.displayName ?? model.slug)
                }
            }
            if let models = decoded.data {
                return models.map { ChatGPTModel(id: $0.id, displayName: $0.id) }
            }
            throw ClaudeClientError.invalidResponse
        } catch let error as ClaudeClientError {
            throw error
        } catch let error as URLError {
            throw Self.clientError(for: error)
        }
    }

    private static func recordsPlanError(_ error: ClaudeClientError) -> Bool {
        switch error {
        case .planUsageLimit, .planNotEligible, .needsReconnect:
            true
        default:
            false
        }
    }

    private static func clientError(for error: URLError) -> ClaudeClientError {
        switch error.code {
        case .notConnectedToInternet:
            .offline
        case .timedOut:
            .timedOut
        case .networkConnectionLost:
            .connectionLost
        default:
            .api(error.localizedDescription)
        }
    }

    private static func error(for status: Int, data: Data) -> ClaudeClientError {
        let body = try? JSONDecoder().decode(ChatGPTModelsErrorBody.self, from: data)
        let error = body?.error
        switch error?.code {
        case "subscription_sharing_usage_limit_exceeded":
            return .planUsageLimit
        case "subscription_sharing_user_not_eligible":
            return .planNotEligible
        case "subscription_sharing_invalid_user":
            return .needsReconnect
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return .rateLimited
        case "subscription_sharing_unsupported_capability":
            return .unsupportedCapability(param: error?.param)
        default:
            break
        }

        if let detail = body?.detail {
            return .api(detail)
        }
        if status == 429 || status == 503 {
            return .rateLimited
        }
        if status == 403 {
            return .api(error?.message ?? "ChatGPT refused the request (403).")
        }
        return .api(error?.message ?? "ChatGPT error \(status).")
    }
}

private struct ChatGPTModelCatalogUnauthorized: Error {}

private struct ChatGPTModelsResponse: Decodable {
    var models: [ListedChatGPTModel]?
    var data: [OpenAIStyleModel]?
}

private struct ListedChatGPTModel: Decodable {
    var slug: String
    var displayName: String?
    var visibility: String?

    enum CodingKeys: String, CodingKey {
        case slug, visibility
        case displayName = "display_name"
    }
}

private struct OpenAIStyleModel: Decodable {
    var id: String
}

private struct ChatGPTModelsErrorBody: Decodable {
    var error: ChatGPTModelsAPIError?
    var detail: String?
}

private struct ChatGPTModelsAPIError: Decodable {
    var code: String?
    var message: String?
    var param: String?
}
