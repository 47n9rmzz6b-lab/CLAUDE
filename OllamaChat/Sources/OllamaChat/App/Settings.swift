import Foundation

/// Clés des réglages enregistrés dans UserDefaults (partagées avec @AppStorage).
enum SettingsKey {
    static let serverURL = "serverURL"
    static let defaultModel = "defaultModel"
    static let systemPrompt = "systemPrompt"
    static let useCustomTemperature = "useCustomTemperature"
    static let temperature = "temperature"
    static let contextLength = "contextLength"
    static let serifResponses = "serifResponses"
}

enum AppDefaults {
    static let serverURL = "http://localhost:11434"
    static let temperature = 0.8

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.serverURL: serverURL,
            SettingsKey.temperature: temperature,
            SettingsKey.contextLength: 0,
            SettingsKey.serifResponses: true,
        ])
    }
}
