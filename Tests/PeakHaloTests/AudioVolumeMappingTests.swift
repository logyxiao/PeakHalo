import Testing
@testable import PeakHalo

@Suite("Audio volume mapping")
struct AudioVolumeMappingTests {
    @Test("Software backend uses square-law gain mapping")
    func softwareBackendUsesSquareLawMapping() {
        #expect(AudioVolumeMapping.gainPercent(forSliderPercent: 50, backend: .software) == 25)
        #expect(AudioVolumeMapping.sliderPercent(forGainPercent: 25, backend: .software) == 50)
    }

    @Test("Hardware and display backends keep linear system gain")
    func hardwareAndDisplayBackendsStayLinear() {
        #expect(AudioVolumeMapping.gainPercent(forSliderPercent: 37, backend: .hardware) == 37)
        #expect(AudioVolumeMapping.sliderPercent(forGainPercent: 37, backend: .hardware) == 37)
        #expect(AudioVolumeMapping.gainPercent(forSliderPercent: 62, backend: .display) == 62)
        #expect(AudioVolumeMapping.sliderPercent(forGainPercent: 62, backend: .display) == 62)
    }

    @Test("Mapping clamps invalid percentages")
    func clampsInvalidPercentages() {
        #expect(AudioVolumeMapping.gainPercent(forSliderPercent: -10, backend: .software) == 0)
        #expect(AudioVolumeMapping.gainPercent(forSliderPercent: 120, backend: .hardware) == 100)
        #expect(AudioVolumeMapping.sliderPercent(forGainPercent: .nan, backend: .display) == 0)
    }
}
