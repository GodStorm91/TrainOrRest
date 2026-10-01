import Foundation

enum ChatGPTAuthConfiguration {
    static let issuer = "https://auth.openai.com"
    static let authorizationEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let revocationEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
    static let discoveryEndpoint = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let planScope = "chatgpt.tokens.use.direct"
    static let registrationClientID = "dynamic_agent_client"
    static let agentName = "TrainOrRest"
    static let callbackPath = "/auth/callback"
    static let completionScheme = "trainorrest"
    static let completionURL = URL(string: "trainorrest://chatgpt-auth-done")!

    static func callbackURL(port: UInt16) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = callbackPath
        return components.url!
    }
}
