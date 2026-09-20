import AppKit
import Combine
import CoreBluetooth
import Foundation
import IOKit
import IOKit.hid

/// A wireless accessory with a battery of its own: AirPods, a Magic Keyboard, a
/// mouse from another maker. Apple's report their charge to macOS itself; the
/// rest over the standard Bluetooth battery service, when they offer it.
struct AccessoryBattery: Identifiable, Equatable {
    enum Kind: Equatable {
        case headphones, keyboard, mouse, trackpad, other
        /// The charging case of a pair of earbuds, a battery of its own beside them.
        case chargingCase
        /// This Mac's own battery, when the widget is set to show it among the accessories.
        case mac

        var symbolName: String {
            switch self {
            case .headphones: return "airpodspro"
            case .chargingCase: return "airpodspro.chargingcase.wireless"
            case .keyboard: return "keyboard"
            case .mouse: return "magicmouse"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .other: return "dot.radiowaves.left.and.right"
            case .mac: return "laptopcomputer"
            }
        }

        /// What an accessory is, from its name — the one thing every source has.
        static func inferred(from name: String) -> Kind {
            let lowered = name.lowercased()
            let keyboard = ["keyboard", "mx keys", "mx mechanical", "k380", "k780", "keychron", "nuphy"]
            let trackpad = ["trackpad", "touchpad"]
            let mouse = ["mouse", "mx master", "mx anywhere", "mx vertical", "mx ergo", "trackball", "lift", "m720", "m575"]
            let headphones = ["airpods", "beats", "headphone", "earbud", "buds", "headset", "wh-", "wf-", "openrun", "shokz"]
            if keyboard.contains(where: lowered.contains) { return .keyboard }
            if trackpad.contains(where: lowered.contains) { return .trackpad }
            if mouse.contains(where: lowered.contains) { return .mouse }
            if headphones.contains(where: lowered.contains) { return .headphones }
            return .other
        }
    }

    /// One battery in the accessory: a pair of earbuds has two, most things one.
    struct Part: Equatable {
        /// Left or Right; nil for the only battery there is.
        var label: String?
        /// 0–100.
        var level: Int
    }

    var id: String
    var name: String
    var kind: Kind
    var parts: [Part]
    var isCharging = false

    /// The lowest level, being the one that runs out first.
    var level: Int { parts.map(\.level).min() ?? 0 }

    /// Every part with its level: "Left 80% · Right 75%", or just "66%".
    var detail: String {
        let levels = parts.map { part in
            part.label.map { "\($0) \(part.level)%" } ?? "\(part.level)%"
        }.joined(separator: " · ")
        return isCharging ? "\(levels) · Charging" : levels
    }

    static let macID = "mac"

    /// This Mac's battery, in the shape of an accessory.
    static func mac(_ status: BatteryStatus) -> AccessoryBattery {
        AccessoryBattery(id: macID, name: "This Mac", kind: .mac, parts: [Part(label: nil, level: status.level)], isCharging: status.isCharging)
    }
}

/// The batteries of the accessories connected to this Mac, for the accessories
/// widget. Two sources: the IORegistry, where every accessory that reports its
/// charge to macOS — Apple's — sits with `HasBattery` set, needing no permission;
/// and the Bluetooth battery service that accessories from other makers offer,
/// read over CoreBluetooth, for which macOS asks once whether the app may use
/// Bluetooth. Accessories update their level rarely, so both are polled every
/// half minute while a widget is on screen, and again when the Mac wakes; the
/// Bluetooth ones also push a change as it happens.
@MainActor
final class AccessoryBatteryMonitor: ObservableObject {
    static let shared = AccessoryBatteryMonitor()

    @Published private(set) var devices: [AccessoryBattery] = []
    /// Whether Bluetooth access has been refused, so the editor can say why a
    /// mouse from another maker is missing.
    @Published private(set) var bluetoothDenied = false

    private var registryDevices: [AccessoryBattery] = []
    private let bluetooth = BluetoothBatteryReader()
    private var poller: Task<Void, Never>?
    private var wakeToken: NSObjectProtocol?
    private var subscribers = 0

    private init() {
        bluetooth.onChange = { [weak self] in self?.publish() }
    }

    // MARK: - Lifecycle

    /// Polling only runs while at least one widget is on screen. The first
    /// widget also brings up macOS's Bluetooth dialog, once.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        bluetooth.start()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        poller?.cancel()
        poller = nil
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        wakeToken = nil
        bluetooth.stop()
        registryDevices = []
        devices = []
    }

    static func openBluetoothSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
        NSWorkspace.shared.open(url)
    }

    static func openBluetoothPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Reading

    private func poll() async {
        bluetooth.refresh()
        // Walking the registry is a handful of Mach calls; off the main thread all the same.
        registryDevices = await Task.detached(priority: .utility) { AccessoryBatteryReader.devices() }.value
        publish()
    }

    /// The registry's devices, then the Bluetooth ones it does not already have —
    /// an accessory can be reachable both ways, and the registry's name is the
    /// one the user knows. A steady order, so the tiles do not shuffle as levels
    /// change.
    private func publish() {
        var merged = registryDevices
        let known = Set(merged.map { $0.name.lowercased() })
        merged += bluetooth.devices.filter { !known.contains($0.name.lowercased()) }
        merged.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        if merged != devices { devices = merged }
        let denied = bluetooth.isDenied
        if denied != bluetoothDenied { bluetoothDenied = denied }
    }
}

/// Reads the standard Bluetooth battery service (`180F`, level `2A19`) of every
/// accessory the Mac is connected to that offers it — a Logitech mouse, most
/// headphones. The Mac holds the connection already; connecting from here only
/// joins it, and dropping it again leaves the accessory connected to the Mac.
/// Levels are read on each refresh and pushed by the accessory in between.
/// Everything runs on the main queue.
private final class BluetoothBatteryReader: NSObject {
    var onChange: (() -> Void)?

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var levels: [UUID: Int] = [:]

    var isDenied: Bool {
        central != nil && [.denied, .restricted].contains(CBCentralManager.authorization)
    }

    var devices: [AccessoryBattery] {
        peripherals.compactMap { id, peripheral in
            guard let level = levels[id] else { return nil }
            let name = peripheral.name ?? "Accessory"
            return AccessoryBattery(
                id: "bluetooth-\(id.uuidString)",
                name: name,
                kind: AccessoryBattery.Kind.inferred(from: name),
                parts: [AccessoryBattery.Part(label: nil, level: level)]
            )
        }
    }

    /// Creating the manager is what brings up macOS's Bluetooth dialog.
    func start() {
        guard central == nil else { refresh(); return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        for peripheral in peripherals.values { central?.cancelPeripheralConnection(peripheral) }
        peripherals = [:]
        levels = [:]
        central = nil
    }

    /// Picks up accessories that connected since, lets go of ones that left, and
    /// reads every level again.
    func refresh() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let present = Set(connected.map(\.identifier))
        for (id, peripheral) in peripherals where !present.contains(id) {
            central.cancelPeripheralConnection(peripheral)
            peripherals[id] = nil
            levels[id] = nil
        }
        for peripheral in connected {
            if peripherals[peripheral.identifier] == nil {
                peripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
            if peripheral.state == .connected {
                read(peripheral)
            } else if peripheral.state == .disconnected {
                central.connect(peripheral)
            }
        }
        onChange?()
    }

    private func read(_ peripheral: CBPeripheral) {
        if let characteristic = levelCharacteristic(of: peripheral) {
            peripheral.readValue(for: characteristic)
        } else {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    private func levelCharacteristic(of peripheral: CBPeripheral) -> CBCharacteristic? {
        peripheral.services?
            .first { $0.uuid == Self.batteryService }?
            .characteristics?
            .first { $0.uuid == Self.batteryLevel }
    }
}

extension BluetoothBatteryReader: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            refresh()
        } else {
            levels = [:]
            onChange?()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        read(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        levels[peripheral.identifier] = nil
        onChange?()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = levelCharacteristic(of: peripheral) else { return }
        peripheral.readValue(for: characteristic)
        // Accessories that can push a change do so through notifications.
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel, let level = characteristic.value?.first else { return }
        levels[peripheral.identifier] = min(100, Int(level))
        onChange?()
    }
}

/// Walks the IORegistry for accessories with a battery — the Apple ones, which
/// report their charge to macOS itself. An accessory's own entry
/// often has no name — a Magic Keyboard's `Product` can be empty — while its HID
/// device, found by the shared `LocationID`, always has one.
private enum AccessoryBatteryReader {
    static func devices() -> [AccessoryBattery] {
        let matching = IOServiceMatching("IOService") as NSMutableDictionary
        matching[kIOPropertyMatchKey] = ["HasBattery": true]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        let names = hidProductNames()
        var devices: [AccessoryBattery] = []
        var seen: Set<String> = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let properties = registryProperties(of: service),
                  // The Mac's own battery is a power source, not an accessory.
                  (properties["Built-In"] as? Bool) != true else { continue }
            let parts = batteryParts(in: properties)
            let caseLevel = level(properties["BatteryPercentCase"])
            guard !parts.isEmpty || caseLevel != nil else { continue }

            let location = (properties["LocationID"] as? NSNumber)?.uint32Value
            let name = location.flatMap { names[$0] }
                ?? nonEmpty(properties["Product"])
                ?? inferredName(from: properties)
            let id = identifier(location: location, properties: properties, name: name)
            guard seen.insert(id).inserted else { continue }
            if !parts.isEmpty {
                devices.append(AccessoryBattery(
                    id: id, name: name, kind: kind(for: name, properties: properties), parts: parts,
                    isCharging: isCharging(properties, suffixes: ["", "Left", "Right"])
                ))
            }
            // The case is a battery of its own, shown beside the earbuds as macOS does.
            if let caseLevel {
                devices.append(AccessoryBattery(
                    id: "\(id)-case", name: "\(name) Case", kind: .chargingCase,
                    parts: [AccessoryBattery.Part(label: nil, level: caseLevel)],
                    isCharging: isCharging(properties, suffixes: ["Case"])
                ))
            }
        }
        // A steady order, so the chips do not shuffle as levels change.
        return devices.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private static func batteryParts(in properties: [String: Any]) -> [AccessoryBattery.Part] {
        let keys: [(String, String?)] = [
            ("BatteryPercent", nil),
            ("BatteryPercentLeft", "Left"),
            ("BatteryPercentRight", "Right"),
        ]
        return keys.compactMap { key, label in
            level(properties[key]).map { AccessoryBattery.Part(label: label, level: $0) }
        }
    }

    private static func level(_ value: Any?) -> Int? {
        (value as? NSNumber).map { min(100, max(0, $0.intValue)) }
    }

    /// Whether any of the batteries is charging: bit 1 of `BatteryStatusFlags`
    /// (and its Left/Right/Case forms), the one seen set while a Magic Keyboard
    /// charges over its cable. Not documented, so a wrong bit costs only the bolt.
    private static func isCharging(_ properties: [String: Any], suffixes: [String]) -> Bool {
        suffixes.contains { suffix in
            guard let flags = (properties["BatteryStatusFlags\(suffix)"] as? NSNumber)?.intValue else { return false }
            return flags & 0b10 != 0
        }
    }

    /// Without a name, the kind of connection still says what the accessory is.
    private static func inferredName(from properties: [String: Any]) -> String {
        let notification = nonEmpty(properties["ConnectionNotificationType"]) ?? ""
        if notification.hasPrefix("KB") { return "Keyboard" }
        if notification.hasPrefix("TP") { return "Trackpad" }
        if notification.hasPrefix("M") { return "Mouse" }
        return "Accessory"
    }

    private static func kind(for name: String, properties: [String: Any]) -> AccessoryBattery.Kind {
        let inferred = AccessoryBattery.Kind.inferred(from: name)
        if inferred != .other { return inferred }
        if properties["BatteryPercentLeft"] != nil || properties["BatteryPercentRight"] != nil { return .headphones }
        switch inferredName(from: properties) {
        case "Keyboard": return .keyboard
        case "Trackpad": return .trackpad
        case "Mouse": return .mouse
        default: return .other
        }
    }

    private static func identifier(location: UInt32?, properties: [String: Any], name: String) -> String {
        if let location { return "location-\(location)" }
        if let address = nonEmpty(properties["DeviceAddress"]) { return "address-\(address)" }
        if let serial = nonEmpty(properties["SerialNumber"]) { return "serial-\(serial)" }
        return "name-\(name)"
    }

    private static func registryProperties(of service: io_registry_entry_t) -> [String: Any]? {
        var reference: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &reference, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return reference?.takeRetainedValue() as? [String: Any]
    }

    /// Product names of every HID device, by location id.
    private static func hidProductNames() -> [UInt32: String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let hidDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [:] }
        var names: [UInt32: String] = [:]
        for device in hidDevices {
            guard let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.uint32Value,
                  let name = nonEmpty(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)) else { continue }
            names[location] = name
        }
        return names
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }
}
