# PeakHalo Architecture Improvement Plan

Generated from the architecture review report in `/tmp` on 2026-06-13.

## Context

The codebase has several shallow modules where the interface exposes nearly as much complexity as the implementation. The goal is to deepen modules so callers get more leverage and maintainers get better locality.

Current note: this plan assumes the screenshot/recording hiding feature has been removed. That deletion should remain unless explicitly reintroduced with a different design.

## Candidate 1 — Deepen the Audio Engine module

**Recommendation:** Strong

**Files involved:**

- `Sources/PeakHalo/Stores/AudioControlStore.swift`
- `Sources/PeakHalo/Services/AudioProcessTapService.swift`
- `Sources/PeakHalo/Services/SystemAudioVolumeService.swift`
- `Sources/PeakHalo/Services/AudioProcessService.swift`
- `Sources/PeakHalo/Models/AudioModels.swift`
- `Sources/PeakHalo/Views/AudioControlsView.swift`

**Problem:** `AudioControlStore` is shallow and too broad. Its interface exposes permission state, device state, app state, route intent, tap lifecycle, persistence, fallback routing, and user messages.

**Solution:** Introduce a deeper Audio Engine module that owns audio state and user intents. UI modules should read published state and call intent methods only.

**Benefits:**

- Locality: route/tap/permission bugs concentrate in one module.
- Leverage: one interface becomes the test surface.
- UI stops coordinating audio implementation details.
- Future FineTune migration steps have a named module to extend.

**Initial implementation approach:**

1. Avoid a big-bang rewrite.
2. First extract smaller internal modules from `AudioControlStore` where tests already exist or can be added.
3. Keep public UI behavior unchanged.
4. Move toward an `AudioEngine` facade after lower-risk extractions prove stable.

## Candidate 2 — Split tap lifecycle from render pipeline

**Recommendation:** Strong

**Files involved:**

- `Sources/PeakHalo/Services/AudioProcessTapService.swift`
- `Sources/PeakHalo/Services/AudioEqualizerProcessor.swift`
- `Sources/PeakHalo/Services/AudioSoftLimiter.swift`
- `Tests/PeakHaloTests/AudioProcessTapRenderTests.swift`

**Problem:** `AudioProcessTapService` mixes CoreAudio object ownership with real-time sample transformation. The module has a wide implementation and a confusing test surface.

**Solution:** Extract a dedicated Render Pipeline module. `AudioProcessTapService` should own tap lifecycle; the Render Pipeline should own buffer mapping, gain, equalizer, limiter, and preferred stereo channel behavior.

**Benefits:**

- Locality: audio glitches isolate to render code.
- Leverage: render tests hit one interface.
- Tap lifecycle failures stay separate from sample transformation.
- Real-time constraints become easier to see.

**Initial implementation approach:**

1. Create `AudioRenderPipeline.swift`.
2. Move render state and buffer mapping out of `AudioProcessTapService`.
3. Keep existing tests and point them at the new module.
4. Run full test suite.

## Candidate 3 — Extract a Panel Presentation module

**Recommendation:** Worth exploring

**Files involved:**

- `Sources/PeakHalo/Notch/NotchWindowManager.swift`
- `Sources/PeakHalo/Notch/NotchGeometry.swift`
- `Sources/PeakHalo/Services/MenuBarStatusItemController.swift`
- `Sources/PeakHalo/Models/DisplayPreferences.swift`

**Problem:** `NotchWindowManager` owns both window inventory and menu bar presentation state. It knows about activation mode, anchor rects, dismissal monitoring, closing animation state, display sync, geometry, and view model lifecycle.

**Solution:** Extract a Panel Presentation module that resolves panel mode, anchor, target screens, and dismissal semantics. Leave window creation and geometry in narrower modules.

**Benefits:**

- Locality: menu bar panel bugs concentrate.
- Interface names panel intents.
- Geometry remains pure.
- Fewer cross-module assumptions between menu bar icon and notch windows.

## Candidate 4 — Deepen device control backends

**Recommendation:** Worth exploring

**Files involved:**

- `Sources/PeakHalo/Services/SystemAudioVolumeService.swift`
- `Sources/PeakHalo/Services/DisplayControlService.swift`
- `Sources/PeakHalo/Views/DisplayControlsView.swift`
- `Sources/PeakHalo/Models/AudioVolumeMapping.swift`

**Problem:** Device capability detection, persistence, write semantics, and mute semantics repeat across audio and display modules.

**Solution:** Deepen a Device Control module with adapters for CoreAudio, DDC, and software gain.

**Benefits:**

- Two adapters justify the seam.
- Locality: mute semantics concentrate.
- Leverage: one capability model.
- Tests avoid real hardware.

## Candidate 5 — Choose one Update Channel module

**Recommendation:** Speculative

**Files involved:**

- `Sources/PeakHalo/Services/SparkleUpdateService.swift`
- `Sources/PeakHalo/Services/AppUpdateService.swift`
- `Sources/PeakHalo/Stores/AppUpdateStore.swift`
- `Sources/PeakHalo/Views/AboutSettingsView.swift`

**Problem:** Sparkle and GitHub release paths expose release mechanics to the store and view.

**Solution:** Deepen an Update Channel module that chooses an adapter from bundle configuration.

**Benefits:**

- Locality: release policy concentrates.
- One update interface.
- Dev/install split hidden from UI.

## Execution order

1. Split tap lifecycle from render pipeline. **Done:** `AudioRenderPipeline` now owns buffer mapping, gain ramping, equalizer application, limiter application, and preferred stereo channel writes. `AudioProcessTapService` now calls the render module from its IOProc and keeps CoreAudio tap lifecycle ownership.
2. Use that extraction as the first step toward a deeper Audio Engine module. **In progress:** `AudioRouteResolver` now owns route resolution, fallback detection, and software-device processing gain decisions that previously lived inside `AudioControlStore`. `AudioAppSettingsStore` now owns app audio settings persistence, pinned app discovery, and saved app metadata lookup. `AudioAppItemBuilder` now owns running app/audio process grouping and pinned app restoration. `AudioProcessingPlanner` now owns the pure decision logic for deactivate/restart/activate-pending processing actions. `AudioTapResultReducer` now owns tap-result state transitions and permission-failure classification. `AudioControlWorker` now lives in its own module file and owns background refresh plus debounced device volume/mute writes.
3. Extract Panel Presentation if menu bar/notch behavior changes continue. **In progress:** `NotchPanelPresentationState` now owns menu bar panel visible/closing/anchor state and exposes context-retention decisions used by `NotchWindowManager`. `NotchPanelPlacement` now owns menu bar anchor-to-screen resolution and fallback menu bar anchor geometry.
4. Deepen device control backends after audio state is less tangled. **In progress:** `DeviceMutePolicy` now owns shared mute/unmute/restore-volume semantics and is used by DDC display volume and software audio device volume. `SoftwareDeviceVolumeStore` now owns software device volume/mute/restore persistence and processing gain.
5. Revisit update channel only if release/update code changes again.

## Validation rules

After every code modification:

1. Run relevant filtered tests first when available.
2. Run `swift test` before declaring completion.
3. Rebuild the app package when app code changes.
4. Restart the app from the rebuilt bundle so manual testing uses the latest code.

Commands:

```bash
swift test --filter <RelevantSuite>
swift test
./script/package_app.sh
killall PeakHalo 2>/dev/null || true
open "$(pwd)/dist/PeakHalo.app"
```
