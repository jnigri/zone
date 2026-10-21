import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake while a session runs: holds a power assertion that stops idle display
/// sleep, which also holds off system sleep, the screensaver and the idle screen lock.
/// macOS drops the assertion on its own if Zone quits or crashes.
final class Caffeinator {
    private var assertion: IOPMAssertionID?

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.keepAwake) as? Bool ?? true
    }

    func update(active: Bool) {
        if active, isEnabled, assertion == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Zone session running" as CFString,
                &id
            )
            if result == kIOReturnSuccess { assertion = id }
        } else if !(active && isEnabled), let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
        }
    }
}
