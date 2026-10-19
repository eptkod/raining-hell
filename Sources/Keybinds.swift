import Foundation

/// In-game actions the player can rebind on the settings CONTROLS tab. Menu hotkeys, Esc and
/// the number keys stay fixed. While support is being placed, the support and troops keys
/// also pick the west and east run-in sides.
enum KeyAction: String, CaseIterable {
    case selectAll, troops, support, extract, cease, pause, speed, centre, targets, guide
    case detonate
    case panLeft, panRight, panUp, panDown, zoomIn, zoomOut, zoomReset, mute, volumeDown, volumeUp

    var title: String {
        switch self {
        case .selectAll: return "SELECT ALL"
        case .troops: return "TROOPS"
        case .support: return "SUPPORT"
        case .extract: return "EXTRACT"
        case .cease: return "CEASE FIRE"
        case .pause: return "PAUSE"
        case .speed: return "GAME SPEED"
        case .centre: return "CENTRE TROOPS"
        case .targets: return "HVT LIST"
        case .guide: return "FIELD GUIDE"
        case .detonate: return "DETONATE DRONE"
        case .panLeft: return "PAN LEFT"
        case .panRight: return "PAN RIGHT"
        case .panUp: return "PAN UP"
        case .panDown: return "PAN DOWN"
        case .zoomIn: return "ZOOM IN"
        case .zoomOut: return "ZOOM OUT"
        case .zoomReset: return "RESET ZOOM"
        case .mute: return "MUTE"
        case .volumeDown: return "VOLUME −"
        case .volumeUp: return "VOLUME +"
        }
    }
    /// Default key codes (US layout positions).
    var defaultKey: UInt16 {
        switch self {
        case .selectAll: return 0      // A
        case .troops: return 14        // E
        case .support: return 12       // Q
        case .extract: return 7        // X
        case .cease: return 4          // H
        case .pause: return 49         // Space
        case .speed: return 17         // T
        case .centre: return 8         // C
        case .targets: return 31       // O
        case .guide: return 48         // Tab
        case .detonate: return 11      // B
        case .panLeft: return 123
        case .panRight: return 124
        case .panUp: return 126
        case .panDown: return 125
        case .zoomIn: return 24        // =
        case .zoomOut: return 27       // -
        case .zoomReset: return 29     // 0
        case .mute: return 46          // M
        case .volumeDown: return 33    // [
        case .volumeUp: return 30      // ]
        }
    }
}

/// The player's key for each `KeyAction`, matched by physical key code. Saved between
/// launches once `persistent` is set; preview and screenshot runs keep the defaults.
final class Keybinds {
    static let shared = Keybinds()
    private(set) var keys: [KeyAction:UInt16] = [:]
    var persistent = false
    static let defaultsKey = "keybinds"
    /// Keys that keep their fixed meaning and can't be bound: Esc, Return, Delete, Enter and 1-9.
    static let reserved: Set<UInt16> = [53,36,51,76,117, 18,19,20,21,23,22,26,28,25, 83,84,85,86,87,88,89,91,92]
    /// Secondary keys that still work while no action is bound to them.
    static let fallbacks: [UInt16:KeyAction] = [35:.pause, 122:.guide, 44:.guide, 69:.zoomIn, 78:.zoomOut, 82:.zoomReset]

    func key(_ a: KeyAction) -> UInt16 { keys[a] ?? a.defaultKey }
    /// The action a key triggers in the field, if any.
    func action(for code: UInt16) -> KeyAction? {
        if let a = KeyAction.allCases.first(where:{ key($0) == code }) { return a }
        return Self.fallbacks[code]
    }
    var isDefault: Bool { KeyAction.allCases.allSatisfy { key($0) == $0.defaultKey } }

    /// Binds `code` to `a`. An action already on that key swaps onto `a`'s old key.
    @discardableResult func bind(_ a: KeyAction,_ code: UInt16) -> Bool {
        guard !Self.reserved.contains(code), Self.names[code] != nil else { return false }
        let old = key(a)
        if let other = KeyAction.allCases.first(where:{ $0 != a && key($0) == code }) { keys[other] = old }
        keys[a] = code
        save()
        return true
    }
    func reset(_ a: KeyAction) { bind(a,a.defaultKey) }
    func resetAll() { keys = [:]; save() }

    func load() {
        persistent = true
        guard let stored = UserDefaults.standard.dictionary(forKey:Self.defaultsKey) as? [String:Int] else { return }
        var loaded: [KeyAction:UInt16] = [:]
        for (name,code) in stored { if let a = KeyAction(rawValue:name), let c = UInt16(exactly:code), Self.names[c] != nil { loaded[a] = c } }
        // A stored map that binds one key twice is stale or edited; ignore it.
        let used = KeyAction.allCases.map { loaded[$0] ?? $0.defaultKey }
        if Set(used).count == used.count { keys = loaded }
    }
    private func save() {
        guard persistent else { return }
        if isDefault { UserDefaults.standard.removeObject(forKey:Self.defaultsKey); return }
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues:keys.map{ ($0.key.rawValue,Int($0.value)) }),forKey:Self.defaultsKey)
    }

    /// Short label for an action's key, e.g. "Q", "SPACE", "←".
    func label(_ a: KeyAction) -> String { Self.name(key(a)) }
    static func name(_ code: UInt16) -> String { names[code] ?? "KEY \(code)" }
    /// Names of every bindable key, by key code (US layout).
    static let names: [UInt16:String] = {
        var n: [UInt16:String] = [:]
        let letters: [(UInt16,String)] = [(0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),
                                          (45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z")]
        for (c,s) in letters { n[c] = s }
        let others: [(UInt16,String)] = [(29,"0"),(27,"-"),(24,"="),(33,"["),(30,"]"),(42,"\\"),(41,";"),(39,"'"),(43,","),(47,"."),(44,"/"),(50,"`"),
                                         (49,"SPACE"),(48,"TAB"),(123,"←"),(124,"→"),(126,"↑"),(125,"↓"),
                                         (115,"HOME"),(119,"END"),(116,"PG UP"),(121,"PG DN"),
                                         (122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),(101,"F9"),(109,"F10"),(103,"F11"),(111,"F12"),
                                         (82,"NUM 0"),(65,"NUM ."),(67,"NUM *"),(69,"NUM +"),(75,"NUM /"),(78,"NUM -"),(81,"NUM =")]
        for (c,s) in others { n[c] = s }
        return n
    }()
}
