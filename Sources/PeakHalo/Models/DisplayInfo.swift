import AppKit
import CoreGraphics

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let hasPhysicalNotch: Bool

    var displayName: String {
        isMain ? "\(name) · \(String(localized: "Main Display"))" : name
    }
}

extension NSScreen {
    var peakHaloDisplayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(number.uint32Value)
    }
}
