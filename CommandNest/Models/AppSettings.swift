import AppKit
import Carbon
import Foundation

struct GlobalKeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = GlobalKeyboardShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)

        guard carbonModifiers != 0 else {
            return nil
        }

        self.keyCode = keyCode
        self.modifiers = carbonModifiers
    }

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0

        if normalized.contains(.control) {
            result |= UInt32(controlKey)
        }
        if normalized.contains(.option) {
            result |= UInt32(optionKey)
        }
        if normalized.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if normalized.contains(.command) {
            result |= UInt32(cmdKey)
        }

        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Escape"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "Left Arrow"
        case kVK_RightArrow: return "Right Arrow"
        case kVK_UpArrow: return "Up Arrow"
        case kVK_DownArrow: return "Down Arrow"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key \(keyCode)"
        }
    }
}

struct AppSettings: Equatable {
    var modelIDs: [String]
    var selectedModelID: String
    var systemPrompt: String
    var shortcut: GlobalKeyboardShortcut
    var agentModeEnabled: Bool

    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private enum Keys {
        static let modelIDs = "modelIDs"
        static let selectedModelID = "selectedModelID"
        static let systemPrompt = "systemPrompt"
        static let shortcut = "globalShortcut"
        static let agentModeEnabled = "agentModeEnabled"
        static let didMigrateDefaultModelToFreeRouter = "didMigrateDefaultModelToFreeRouter"
        static let didMigrateAgentModeDefault = "didMigrateAgentModeDefault"
    }

    static var defaults: AppSettings {
        AppSettings(
            modelIDs: Constants.defaultModelIDs,
            selectedModelID: Constants.freeRouterModelID,
            systemPrompt: Constants.defaultSystemPrompt,
            shortcut: .defaultShortcut,
            agentModeEnabled: true
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        let defaultSettings = Self.defaults
        let savedModels = defaults.stringArray(forKey: Keys.modelIDs) ?? defaultSettings.modelIDs
        let modelIDs = normalizedModels(savedModels)
        let didMigrateDefaultModel = defaults.bool(forKey: Keys.didMigrateDefaultModelToFreeRouter)
        let selected: String
        if didMigrateDefaultModel {
            selected = defaults.string(forKey: Keys.selectedModelID) ?? defaultSettings.selectedModelID
        } else {
            selected = Constants.freeRouterModelID
            defaults.set(Constants.freeRouterModelID, forKey: Keys.selectedModelID)
            defaults.set(true, forKey: Keys.didMigrateDefaultModelToFreeRouter)
        }
        let systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? defaultSettings.systemPrompt
        let agentModeEnabled: Bool
        if defaults.bool(forKey: Keys.didMigrateAgentModeDefault) {
            agentModeEnabled = defaults.bool(forKey: Keys.agentModeEnabled)
        } else {
            agentModeEnabled = true
            defaults.set(true, forKey: Keys.agentModeEnabled)
            defaults.set(true, forKey: Keys.didMigrateAgentModeDefault)
        }

        let shortcut: GlobalKeyboardShortcut
        if let data = defaults.data(forKey: Keys.shortcut),
           let decoded = try? JSONDecoder().decode(GlobalKeyboardShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = defaultSettings.shortcut
        }

        return AppSettings(
            modelIDs: modelIDs,
            selectedModelID: modelIDs.contains(selected) ? selected : modelIDs[0],
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSettings.systemPrompt : systemPrompt,
            shortcut: shortcut,
            agentModeEnabled: agentModeEnabled
        )
    }

    func save(to defaults: UserDefaults = .standard, notify: Bool = true) {
        let cleanedModels = Self.normalizedModels(modelIDs)
        defaults.set(cleanedModels, forKey: Keys.modelIDs)
        defaults.set(cleanedModels.contains(selectedModelID) ? selectedModelID : cleanedModels[0], forKey: Keys.selectedModelID)
        defaults.set(systemPrompt, forKey: Keys.systemPrompt)
        defaults.set(agentModeEnabled, forKey: Keys.agentModeEnabled)
        defaults.set(true, forKey: Keys.didMigrateDefaultModelToFreeRouter)
        defaults.set(true, forKey: Keys.didMigrateAgentModeDefault)

        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Keys.shortcut)
        }

        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    static func normalizedModels(_ models: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = models
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }

        if cleaned.isEmpty {
            return Constants.defaultModelIDs
        }

        if cleaned.contains(Constants.freeRouterModelID) {
            return cleaned
        }

        return [Constants.freeRouterModelID] + cleaned
    }
}
