import AppKit
import Foundation

final class AppKiller {
    func terminate(
        _ item: ProcessResourceItem,
        force: Bool,
        whitelist: [String] = ProcessProtection.defaultEntries
    ) -> AppKillResult {
        guard !ProcessProtection.isProtected(
            name: item.name,
            bundleIdentifier: item.bundleIdentifier,
            whitelist: whitelist
        ) else {
            return AppKillResult(
                success: false,
                message: String(format: String(localized: "%@ is protected and was not closed."), item.name)
            )
        }

        guard let application = item.application, !application.isTerminated else {
            return AppKillResult(
                success: false,
                message: String(format: String(localized: "%@ is no longer running."), item.name)
            )
        }

        let accepted = force ? application.forceTerminate() : application.terminate()
        let action = force ? String(localized: "force quit") : String(localized: "quit")

        if accepted {
            return AppKillResult(
                success: true,
                message: String(format: String(localized: "Sent %@ request to %@."), action, item.name)
            )
        }

        return AppKillResult(
            success: false,
            message: String(format: String(localized: "%@ rejected the %@ request."), item.name, action)
        )
    }
}
