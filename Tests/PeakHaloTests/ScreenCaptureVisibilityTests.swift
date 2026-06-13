import Testing
@testable import PeakHalo

@Suite("Screen capture visibility")
struct ScreenCaptureVisibilityTests {
    @Test("Detects the system screencapture executable")
    func detectsSystemScreencaptureExecutable() {
        #expect(
            ScreenCaptureProcessDetector.isSystemCaptureProcess(
                processName: nil,
                bundleIdentifier: nil,
                executablePath: "/usr/sbin/screencapture"
            )
        )
    }

    @Test("Detects the system Screenshot app bundle")
    func detectsSystemScreenshotBundle() {
        #expect(
            ScreenCaptureProcessDetector.isSystemCaptureProcess(
                processName: "Screenshot",
                bundleIdentifier: "com.apple.screenshot",
                executablePath: "/System/Applications/Utilities/Screenshot.app/Contents/MacOS/Screenshot"
            )
        )
    }

    @Test("Ignores third-party apps with screenshot-like names outside system paths")
    func ignoresThirdPartyScreenshotLikeNames() {
        #expect(
            !ScreenCaptureProcessDetector.isSystemCaptureProcess(
                processName: "Screenshot",
                bundleIdentifier: "com.example.screenshot",
                executablePath: "/Applications/Screenshot.app/Contents/MacOS/Screenshot"
            )
        )
    }

    @Test("Disabled hiding keeps windows included and visible")
    func disabledHidingKeepsWindowsIncludedAndVisible() {
        let policy = ScreenCaptureWindowPresentationPolicy.resolved(
            hideFromScreenCapture: false,
            isSystemCaptureActive: true
        )

        #expect(policy.sharingPolicy == .included)
        #expect(policy.shouldOrderOut == false)
        #expect(policy.shouldEnsureVisible == true)
    }

    @Test("Enabled hiding excludes windows without ordering out until capture starts")
    func enabledHidingExcludesWindowsBeforeCaptureStarts() {
        let policy = ScreenCaptureWindowPresentationPolicy.resolved(
            hideFromScreenCapture: true,
            isSystemCaptureActive: false
        )

        #expect(policy.sharingPolicy == .excluded)
        #expect(policy.shouldOrderOut == false)
        #expect(policy.shouldEnsureVisible == false)
    }

    @Test("Enabled hiding orders windows out while capture is active")
    func enabledHidingOrdersWindowsOutDuringCapture() {
        let policy = ScreenCaptureWindowPresentationPolicy.resolved(
            hideFromScreenCapture: true,
            isSystemCaptureActive: true
        )

        #expect(policy.sharingPolicy == .excluded)
        #expect(policy.shouldOrderOut == true)
        #expect(policy.shouldEnsureVisible == false)
    }
}
