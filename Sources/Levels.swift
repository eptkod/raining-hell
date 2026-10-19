import Foundation

/// How generously an operation's opening grant is pitched (see LEVEL-CONSTRUCTION.md).
/// Harder operations get their difficulty from the map, never from a starved opening: every
/// grant buys its profile's `kit` outright and never falls below `World.openingFloor`.
enum FundsProfile {
    case generous, standard, tight
    var name: String {
        switch self { case .generous: return "GENEROUS"; case .standard: return "STANDARD"; case .tight: return "TIGHT" }
    }
    /// Requisition the grant must cover on its own: troop offers and support calls, by name.
    var kit: (troops: [String], support: [String]) {
        switch self {
        case .generous: return (["RIFLE SQUAD","GRENADIER","RPG GUNNER"],["SUPPLY CRATE","GUN RUN"])
        case .standard: return (["RIFLE SQUAD","GRENADIER"],["SUPPLY CRATE"])
        case .tight: return (["RIFLE SQUAD"],["GUN RUN"])
        }
    }
}

/// One operation. Each is wider, taller, better reinforced and asks for more points than the
/// one before; balancing them is an edit to `all`. Their maps are laid out in `World.raise`.
struct LevelSpec {
    let name: String
    let operation: String
    let grid: String
    /// Map width in design units (`World.scale` voxels each).
    let columns: Int
    /// Design rows added above the first operation's map. The ground sits that much lower,
    /// and the towers and blocks standing on it rise that much taller.
    let lift: Int
    /// `World.reinforcement` for the level's concrete.
    let reinforcement: Double
    /// Points needed to extract: about the same share of the map's structure points and
    /// objective bonuses on every level (`World.availablePoints`).
    let requirement: Int
    let funds: FundsProfile
    /// Credits the level opens with, before carry-over and bank withdrawals.
    let grant: Int

    static let all = [
        LevelSpec(name:"KESSEL CROSSING",operation:"OPERATION ASHFALL",grid:"48°12′N  016°22′E",
                  columns:720,lift:0,reinforcement:1.0,requirement:150_000,funds:.standard,grant:2_000),
        LevelSpec(name:"MARROW FERRY",operation:"OPERATION CINDER",grid:"47°48′N  013°02′E",
                  columns:864,lift:9,reinforcement:1.15,requirement:295_000,funds:.generous,grant:4_000),
        LevelSpec(name:"IRONGATE PASS",operation:"OPERATION FLINT",grid:"46°37′N  014°18′E",
                  columns:1008,lift:18,reinforcement:1.35,requirement:305_000,funds:.tight,grant:3_000),
        LevelSpec(name:"VESTRA WORKS",operation:"OPERATION FURNACE",grid:"50°05′N  014°25′E",
                  columns:1152,lift:27,reinforcement:1.6,requirement:550_000,funds:.standard,grant:4_500),
        LevelSpec(name:"SAINT ODILE",operation:"OPERATION BELLWETHER",grid:"48°34′N  007°45′E",
                  columns:1336,lift:36,reinforcement:1.85,requirement:1_015_000,funds:.generous,grant:8_000),
        LevelSpec(name:"THE CITADEL",operation:"OPERATION LAST LIGHT",grid:"52°31′N  013°24′E",
                  columns:1584,lift:45,reinforcement:2.1,requirement:1_075_000,funds:.tight,grant:6_000)]
}

extension World {
    /// Credits a kit of troop offers and support calls costs at today's prices.
    static func cost(of kit: (troops: [String], support: [String])) -> Int {
        kit.troops.map { name in offers.first { $0.name == name }!.cost }.reduce(0,+)
            + kit.support.map { name in support.first { $0.name == name }!.cost }.reduce(0,+)
    }
    /// Least any level may open with: a rifle squad and a gun run.
    static var openingFloor: Int { cost(of:(["RIFLE SQUAD"],["GUN RUN"])) }
    /// Points the intact map holds in structure and objective bonuses; terrain is left out.
    var availablePoints: Int {
        var total = objectives.map { $0.bonus }.reduce(0,+)
        for i in voxels.indices where Self.isStructure(voxels[i]) { total += Int(worth[i]) }
        return total
    }

    // MARK: Fronts
    // Kessel Crossing is laid out below from its sector builders; the later fronts, each
    // its own country with its own landmarks, are in `Fronts.swift` and built from the
    // pieces in `Landmarks.swift`.

    /// Ground profile for `level` east of Kessel's rolling landing zone: design-unit
    /// (column, surface row) keys, and the column ranges where the ground is broken up.
    static func terrain(for level: Int) -> ([(x: Int, row: Int)], [Range<Int>]) {
        switch level {
        case 0:
            let deck = bridgeDeck, bed = riverBed
            return ([(179,60),(206,60),(240,deck),(262,deck),(277,bed),(303,bed),(318,deck),(324,deck),(327,58),
                     (578,58),(600,47),(624,33),(694,33),(708,38),(719,41)],[0..<240,579..<624])
        case 1: return (marrowTerrain,[0..<170,760..<864])
        case 2: return (irongateTerrain,[0..<100,175..<230,800..<840])
        case 3: return (vestraTerrain,[0..<90,1070..<1152])
        case 4: return (odileTerrain,[0..<100])
        default: return (citadelTerrain,[0..<100])
        }
    }
    /// Lays out `level`'s structures, objectives and landmarks on its freshly cut terrain.
    func raise(_ level: Int) {
        switch level {
        case 0:
            outpost("OUTPOST BUNKER"); noMansLand()
            town(floors:[3,5,2,4],tower:"CHURCH BELL TOWER")
            crossing("KESSEL BRIDGE")
            works("FUEL DEPOT & STACK")
            fortress(gun:"GUN EMPLACEMENT",depot:"TUNNEL DEPOT")
            landmarks += [Landmark(name:"KESSEL RIVER CROSSING",x:2100,y:500),Landmark(name:"HOLLOWAY / RUINED TOWN",x:2660,y:200),
                          Landmark(name:"WORKS NO. 4",x:3920,y:400)]
        case 1:
            marrowFerry()
        case 2:
            irongatePass()
        case 3:
            vestraWorks()
        case 4:
            saintOdile()
        default:
            citadel()
        }
    }

    // MARK: Sectors

    /// Sector 1 · LZ Alpha's sandbag line and crates, and a small, fully voxel-built
    /// observation bunker.
    func outpost(_ name: String?, dy: Int = 0, bonus: Int = 1500, crates: Bool = true) {
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ m: UInt8) { self.fill(x,y+dy,w,h,m) }
        fill(108, 34, 44, 3, 3)
        fill(108, 37, 3, 20, 3); fill(149, 37, 3, 22, 3)
        fill(108, 46, 44, 2, 3); fill(108, 55, 44, 3, 3)
        fill(120, 37, 2, 9, 3); fill(136, 37, 2, 9, 3)
        fill(113, 40, 7, 5, 4); fill(127, 40, 9, 5, 4); fill(141, 40, 8, 5, 4)
        fill(124, 48, 2, 7, 3); fill(108, 50, 3, 6, 0)
        fill(114, 31, 3, 3, 3); fill(144, 31, 3, 3, 3)
        fill(127, 29, 7, 5, 5)
        fill(129, 24, 1, 5, 11)
        // Sandbag line and cargo crates.
        fill(87, 53, 11, 3, 6)
        if crates { fill(156, 54, 6, 5, 7); fill(163, 55, 5, 5, 7) }
        room(108, 36+dy, 151, 45+dy, floor: 46+dy, ceiling: 36+dy)
        room(108, 46+dy, 151, 54+dy, floor: 55+dy, ceiling: 47+dy)
        fixtures.append(Fixture(x:127,y:49+dy,w:6,h:4))
        if let name { target(name,108,24+dy,152,58+dy,bonus) }
        landmarks.append(Landmark(name:"LZ / ALPHA",x:112,y:602+Double(dy)*8))
    }
    /// Sector 2 · No-man's land: shell craters, a stepped trench, and a burnt-out tank.
    func noMansLand() {
        for (cx,r) in [(188,3),(199,2),(236,4)] { carve(cx, surfaceRow(cx)-1, r+1, r) }
        for i in 0..<18 { fill(209+i, surfaceRow(209+i), 1, min(3,i+1,18-i), 0) }
        fill(227, surfaceRow(227)-1, 4, 1, 6); fill(205, surfaceRow(205)-1, 3, 1, 6)
        let tank = surfaceRow(242)
        fill(240, tank-3, 13, 3, 11); fill(243, tank-5, 6, 2, 11); fill(249, tank-5, 7, 1, 11)
        landmarks.append(Landmark(name:"NO-MAN'S LAND",x:1590,y:500+Double(Self.spec.lift)*8))
    }
    /// Sector 4 · Ruined town east of the first gorge: apartment blocks of `floors` storeys,
    /// a church with a bell tower, and a gutted block. Laid before the bridge, so the bridge's
    /// east ramp meets the road beside the first building's footing.
    func town(dy: Int = 0, floors: [Int], tower: String, bonus: Int = 2000) {
        let base = 58+dy
        building(330, 28, floors[0], base)
        building(366, 20, floors[1], base)
        building(394, 30, floors[2], base, story:12)
        belfry(424, base: base)
        building(444, 26, floors[3], base, hut:false)
        let roof = base-2-floors[3]*9
        fill(458, roof, 12, 9, 0); fill(468, roof-1, 3, 2, 0)
        for (i,h) in [2,3,4,3,2,1].enumerated() { fill(471+i, base-h, 1, h, 10) }
        fill(356, base-2, 6, 2, 6); fill(386, base-3, 4, 3, 7)
        fixtures += [Fixture(x:340,y:base-11,w:5,h:3),Fixture(x:404,y:base-17,w:6,h:4),Fixture(x:375,y:base-38,w:4,h:3)]
        target(tower,424,0,432,base,bonus)
    }
    /// A brick bell tower eight columns wide rising from ground row `base` to row 6, with an
    /// open belfry, a steel bell, and a stepped spire to the top of the map.
    func belfry(_ x: Int, base: Int) {
        fill(x, 6, 8, base-6, 5); fill(x+2, 10, 4, 6, 0); fill(x+3, 10, 2, 2, 11)
        for r in 0..<6 { fill(x+4-(r/2+1), r, (r/2+1)*2, 1, 5) }
    }
    /// Sector 5 · Factory hall, chimney stack, and fuel tanks, `dx` east of the first front's.
    func works(_ name: String, dx: Int = 0, dy: Int = 0, bonus: Int = 4000) {
        let base = 58+dy
        building(488+dx, 56, 1, base, story:16)
        for k in 0..<3 { for r in 1...3 { fill(492+dx+k*12+(r-1)*3, base-18-r, 12-(r-1)*3, 1, 3) } }
        // The stack rises to row 6 whatever the ground, banded with steel every 14 rows.
        fill(548+dx, 6, 5, base-6, 5); fill(547+dx, 6, 7, 2, 11)
        for band in stride(from:20, to:base-10, by:14) { fill(547+dx, band, 7, 1, 11) }
        for cx in [557.5,569.5] {
            let cy = Double(base)-5.5
            for y in base-11...base-1 {
                for x in Int(cx)-5...Int(cx)+6 where pow(Double(x)-cx,2)+pow(Double(y)-cy,2) <= 30 { fill(x+dx,y,1,1,11) }
            }
        }
        fill(496+dx, base-6, 5, 4, 7); fill(506+dx, base-5, 4, 3, 7); fill(527+dx, base-6, 5, 4, 7)
        fixtures.append(Fixture(x:514+dx,y:base-14,w:8,h:4))
        target(name,546+dx,6,577+dx,base,bonus)
    }
    /// Sector 6 · Ridge fortress, gun emplacement, and a concrete-lined tunnel depot.
    func fortress(dx: Int = 0, dy: Int = 0, gun: String, depot: String, bonus: (gun: Int, depot: Int) = (3000,4000)) {
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ m: UInt8) { self.fill(x+dx,y+dy,w,h,m) }
        self.fill(586+dx, surfaceRow(586+dx)-1, 6, 1, 6)
        self.fill(612+dx, surfaceRow(612+dx)-1, 5, 1, 6)
        building(630+dx, 34, 2, 33+dy, story:8)
        // The fortress already sits at the limit of its overhang over the depot: no west-face trim.
        fill(629, 15, 1, 1, 0); fill(629, 23, 1, 1, 0)
        fill(646, 7, 1, 8, 11); fill(647, 7, 4, 3, 5)
        fill(672, 29, 14, 4, 3); fill(676, 24, 8, 5, 11); fill(667, 25, 9, 2, 11)
        fill(690, 31, 6, 2, 6)
        // Shallow depot: the ridge and fortress rest on a ceiling slab carried by
        // close-set columns placed under the fortress walls.
        fill(604, 38, 96, 9, 0)
        fill(604, 38, 96, 2, 3); fill(600, 47, 100, 2, 3)
        for cx in [620,631,646,662,677,690] { fill(cx, 40, 2, 7, 3) }
        fill(697, 40, 3, 7, 3)
        room(604+dx, 39+dy, 696+dx, 46+dy, floor: 47+dy, ceiling: 39+dy)
        fill(630, 33, 34, 5, 3)
        fill(650, 43, 4, 4, 7); fill(655, 44, 4, 3, 7); fill(667, 45, 7, 2, 6)
        fixtures += [Fixture(x:623+dx,y:42+dy,w:6,h:3),Fixture(x:640+dx,y:26+dy,w:5,h:3)]
        target(gun,667+dx,24+dy,686+dx,33+dy,bonus.gun)
        target(depot,600+dx,38+dy,700+dx,49+dy,bonus.depot)
        landmarks += [Landmark(name:"RIDGE FORTRESS",x:5040+Double(dx)*8,y:150+Double(dy)*8),
                      Landmark(name:depot,x:4900+Double(dx)*8,y:470+Double(dy)*8)]
    }
}
