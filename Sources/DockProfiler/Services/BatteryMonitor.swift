import Foundation
import IOKit.ps

struct BatteryStatus: Equatable {
    /// 0–100.
    var level: Int
    var isCharging: Bool
    var isOnACPower: Bool

    /// The internal battery, or nil on a Mac without one.
    static func current() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else { return nil }
        for source in list as [CFTypeRef] {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = info[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryStatus(
                level: maximum > 0 ? min(100, capacity * 100 / maximum) : capacity,
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                isOnACPower: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}

/// Publishes the battery state, refreshed whenever IOKit says a power source changed
/// — plugging in, unplugging, or the level ticking over.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var status: BatteryStatus?
    private var source: CFRunLoopSource?

    private init() {
        status = BatteryStatus.current()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.status = BatteryStatus.current() }
        }, context)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
