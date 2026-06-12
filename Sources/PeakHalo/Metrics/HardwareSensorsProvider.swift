import Foundation

protocol HardwareSensorsProvider {
    func sampleHardwareSensors() -> HardwareSensors
}

final class DefaultHardwareSensorsProvider: HardwareSensorsProvider {
    func sampleHardwareSensors() -> HardwareSensors {
        HardwareSensors(
            cpuTemperatureCelsius: nil,
            fanSpeedRPM: nil,
            source: .unavailable,
            message: "Hardware sensors require a helper or supported sensor backend.",
            updatedAt: Date()
        )
    }
}
