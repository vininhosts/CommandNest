import Foundation

enum Constants {
    static let appName = "CommandNest"
    static let bundleIdentifier = "io.github.vininhosts.CommandNest"
    static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    static let openRouterModelsEndpoint = "https://openrouter.ai/api/v1/models"
    static let openRouterReferer = "https://github.com/vininhosts/CommandNest"
    static let openRouterTitle = "CommandNest"
    static let gitHubRepository = "vininhosts/CommandNest"
    static let gitHubReleasesURL = "https://github.com/vininhosts/CommandNest/releases"
    static let gitHubLatestReleaseAPIURL = "https://api.github.com/repos/vininhosts/CommandNest/releases/latest"
    static let onboardingCompletedDefaultsKey = "hasCompletedOnboarding"
    static let freeRouterModelID = "openrouter/free"
    static let manifestFolderName = "CommandNest-Manifests"
    static let legacyManifestFolderName = "ShortcutAI-Manifests"

    static let defaultSystemPrompt = "You are a concise, helpful desktop AI assistant."

    static let defaultModelIDs = [
        freeRouterModelID,
        "openai/gpt-4o-mini",
        "anthropic/claude-3.5-haiku",
        "google/gemini-flash-1.5",
        "meta-llama/llama-3.1-8b-instruct"
    ]
}
