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
}
