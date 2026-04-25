import Carbon
import XCTest
@testable import CommandNest

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CommandNestTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testDefaultsUseFreeRouterAndAgentMode() {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.selectedModelID, Constants.freeRouterModelID)
        XCTAssertEqual(settings.modelIDs.first, Constants.freeRouterModelID)
        XCTAssertTrue(settings.agentModeEnabled)
    }

    func testModelNormalizationDeduplicatesAndPrependsFreeRouter() {
        let models = AppSettings.normalizedModels([
            "openai/gpt-4o-mini",
            "openai/gpt-4o-mini, anthropic/claude-3.5-haiku",
            " "
        ])

        XCTAssertEqual(models, [
            Constants.freeRouterModelID,
            "openai/gpt-4o-mini",
            "anthropic/claude-3.5-haiku"
        ])
    }

    func testFirstLoadMigratesSelectedModelToFreeRouter() {
        defaults.set("openai/gpt-4o-mini", forKey: "selectedModelID")
        defaults.set(["openai/gpt-4o-mini"], forKey: "modelIDs")

        let settings = AppSettings.load(from: defaults)

        XCTAssertEqual(settings.selectedModelID, Constants.freeRouterModelID)
        XCTAssertEqual(defaults.string(forKey: "selectedModelID"), Constants.freeRouterModelID)
    }

    func testSaveAndLoadPersistsShortcutAndAgentMode() {
        let shortcut = GlobalKeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey))
        let settings = AppSettings(
            modelIDs: ["custom/model"],
            selectedModelID: "custom/model",
            systemPrompt: "You are direct.",
            shortcut: shortcut,
            agentModeEnabled: false
        )

        settings.save(to: defaults, notify: false)
        let loaded = AppSettings.load(from: defaults)

        XCTAssertEqual(loaded.selectedModelID, "custom/model")
        XCTAssertEqual(loaded.systemPrompt, "You are direct.")
        XCTAssertEqual(loaded.shortcut, shortcut)
        XCTAssertFalse(loaded.agentModeEnabled)
    }
}
