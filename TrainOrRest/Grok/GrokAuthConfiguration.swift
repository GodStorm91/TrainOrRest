import Foundation

enum GrokAuthConfiguration {
    /// Published omp / pi-ai xAI OAuth client. Not a secret; the device-code flow has no client secret.
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let scope = "openid profile email offline_access grok-cli:access api:access"
    static let issuer = URL(string: "https://auth.x.ai")!
    static let deviceCodeURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    static let discoveryURL = URL(string: "https://auth.x.ai/.well-known/openid-configuration")!
    static let userInfoURL = URL(string: "https://auth.x.ai/oauth2/userinfo")!
    static let responsesURL = URL(string: "https://api.x.ai/v1/responses")!
    static let defaultModel = "grok-4.6"
    static let models = ["grok-4.7", "grok-4.6", "grok-4.5"]
    /// Matches omp's client-side access-token expiry skew.
    static let accessTokenSkew: TimeInterval = 5 * 60
}
