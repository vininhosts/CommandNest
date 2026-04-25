import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionService {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func openFullDiskAccessSettings() {
        openPrivacyPane("Privacy_AllFiles")
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    private static func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
