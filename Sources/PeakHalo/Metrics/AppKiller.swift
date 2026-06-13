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
                message: LocalizedMessage(
                    "%@ is protected and was not closed.",
                    arguments: [.string(item.name)]
                )
            )
        }

        guard let application = item.application, !application.isTerminated else {
            return AppKillResult(
                success: false,
                message: LocalizedMessage(
                    "%@ is no longer running.",
                    arguments: [.string(item.name)]
                )
            )
        }

        let accepted = force ? application.forceTerminate() : application.terminate()
        let action = LocalizedMessage.string(force ? "force quit" : "quit")

        if accepted {
            return AppKillResult(
                success: true,
                message: LocalizedMessage(
                    "Sent %@ request to %@.",
                    arguments: [.message(action), .string(item.name)]
                )
            )
        }

        return AppKillResult(
            success: false,
            message: LocalizedMessage(
                "%@ rejected the %@ request.",
                arguments: [.string(item.name), .message(action)]
            )
        )
    }
}
