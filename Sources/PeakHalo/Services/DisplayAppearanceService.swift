import Foundation

struct DisplayAppearanceState: Equatable {
    var isNightShiftAvailable: Bool
    var isNightShiftEnabled: Bool
    var isTrueToneAvailable: Bool
    var isTrueToneEnabled: Bool
}

final class DisplayAppearanceService {
    private let blueLightClient: NSObject?
    private let trueToneClient: NSObject?

    init() {
        blueLightClient = NSClassFromString("CBBlueLightClient")
            .flatMap { ($0 as? NSObject.Type)?.init() }
        trueToneClient = NSClassFromString("CBTrueToneClient")
            .flatMap { ($0 as? NSObject.Type)?.init() }
    }

    func state() -> DisplayAppearanceState {
        DisplayAppearanceState(
            isNightShiftAvailable: isNightShiftAvailable,
            isNightShiftEnabled: isNightShiftEnabled,
            isTrueToneAvailable: isTrueToneAvailable,
            isTrueToneEnabled: isTrueToneEnabled
        )
    }

    func setNightShiftEnabled(_ isEnabled: Bool) -> Bool {
        guard let blueLightClient else { return false }
        return blueLightClient.performBoolSelector("setEnabled:", with: isEnabled)
    }

    func setTrueToneEnabled(_ isEnabled: Bool) -> Bool {
        guard isTrueToneAvailable,
              let trueToneClient else {
            return false
        }
        return trueToneClient.performBoolSelector("setEnabled:", with: isEnabled)
    }

    private var isNightShiftAvailable: Bool {
        guard let blueLightClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type,
              blueLightClass.responds(to: NSSelectorFromString("supportsBlueLightReduction")) else {
            return blueLightClient != nil
        }

        return blueLightClass.performBoolSelector("supportsBlueLightReduction")
    }

    private var isNightShiftEnabled: Bool {
        guard let blueLightClient else { return false }
        return blueLightClient.blueLightEnabled()
    }

    private var isTrueToneAvailable: Bool {
        guard let trueToneClient else { return false }
        if trueToneClient.responds(to: NSSelectorFromString("supported")),
           !trueToneClient.performBoolSelector("supported") {
            return false
        }
        if trueToneClient.responds(to: NSSelectorFromString("available")),
           !trueToneClient.performBoolSelector("available") {
            return false
        }
        return true
    }

    private var isTrueToneEnabled: Bool {
        guard let trueToneClient else { return false }
        return trueToneClient.performBoolSelector("enabled")
    }
}

private extension NSObject {
    func performBoolSelector(_ selectorName: String) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        let implementation = method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(self, selector)
    }

    func performBoolSelector(_ selectorName: String, with value: Bool) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let implementation = method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(self, selector, value)
    }

    func blueLightEnabled() -> Bool {
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard responds(to: selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let implementation = method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        var statusBytes = [UInt8](repeating: 0, count: 64)
        let success = statusBytes.withUnsafeMutableBytes { buffer in
            function(self, selector, buffer.baseAddress!)
        }
        return success && statusBytes.indices.contains(1) && statusBytes[1] != 0
    }

    static func performBoolSelector(_ selectorName: String) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector) else { return false }
        typealias Function = @convention(c) (AnyClass, Selector) -> Bool
        let implementation = method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(self, selector)
    }
}
