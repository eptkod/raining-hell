import Foundation

enum SoundCue: String { case shot, explosion, collapse, rubble, glass, step, deploy, order, cease, select, pause, reset, plane, jet, gun }
struct SoundEvent { var cue: SoundCue; var x: Double? = nil; var gain: Double = 1 }

struct Vec {
    var x: Double
    var y: Double
    static func + (a: Vec, b: Vec) -> Vec { Vec(x: a.x+b.x, y: a.y+b.y) }
    static func * (a: Vec, b: Double) -> Vec { Vec(x: a.x*b, y: a.y*b) }
}
/// Troop types the requisition menu can deploy.
/// Riflemen and grenadiers auto-aim: `World.launch` solves the arc onto their `target`.
/// The RPG gunner is aimed by hand instead (`manualAim`): it never takes an attack target,
/// and fires one rocket per click straight at the pointer (see `World.fireRockets`).
enum TroopKind {
    case rifleman, grenadier, rpg
    /// Radius of each round's impact blast.
    var blastRadius: Double {
        switch self { case .rifleman: return World.bulletBlastRadius; case .grenadier: return 22; case .rpg: return 34 }
    }
    /// Base seconds between rounds; auto-aimed troops add a random spread on top.
    var reload: Double {
        switch self { case .rifleman: return 1.2; case .grenadier: return 3.6; case .rpg: return 7 }
    }
    /// Rounds carried into battle; a supply crate refills to this.
    var magazine: Int {
        switch self { case .rifleman: return 40; case .grenadier: return 12; case .rpg: return 7 }
    }
    /// Walking pace in px/s. Riflemen chip rather than demolish, so they make up for it in mobility.
    var walkSpeed: Double {
        switch self { case .rifleman: return 92; case .grenadier: return 46; case .rpg: return 44 }
    }
    /// Fired by the player, one shot per click, rather than at an attack target.
    var manualAim: Bool { self == .rpg }
    var name: String {
        switch self { case .rifleman: return "RIFLEMAN"; case .grenadier: return "GRENADIER"; case .rpg: return "RPG GUNNER" }
    }
}
struct Soldier {
    var id: Int
    var position: Vec
    var kind: TroopKind = .rifleman
    var selected = true
    var cooldown: Double = 0
    /// Rounds left. Soldiers keep their attack order when empty and resume once resupplied.
    var ammo = TroopKind.rifleman.magazine
    /// Seconds left on the "rearmed" cue after a supply crate refills this soldier.
    var rearmed: Double = 0
    var target: Vec? = nil
    var moveX: Double? = nil
    /// Columns to walk through to reach `moveX`, planned around walls and rubble.
    var route: [Int] = []
    var routed = false
    var stuck: Double = 0
    var facing: Double = 1
    var stride: Double = 0
    var flash: Double = 0
    var falling: Double = 0
    /// Drawn size relative to the original 38 px sprite.
    static let drawScale = 0.6
    static let muzzle = Vec(x:15*drawScale,y:23*drawScale)
    static let height = 38*drawScale
    /// Mouth of the RPG's shoulder tube, which sits higher and further forward than a rifle.
    static let tubeMuzzle = Vec(x:34*drawScale,y:27*drawScale)
    /// Where this soldier's rounds leave the barrel.
    var muzzleOrigin: Vec {
        let m = kind == .rpg ? Self.tubeMuzzle : Self.muzzle
        return Vec(x:position.x+facing*m.x,y:position.y-m.y)
    }
    /// At or below a quarter of a full load.
    var lowAmmo: Bool { ammo > 0 && ammo*4 <= kind.magazine }
    var outOfAmmo: Bool { ammo <= 0 }
    /// An RPG gunner between rockets. Reloading is shown nowhere on the map; it only slows the gunner.
    var reloading: Bool { kind.manualAim && cooldown > 0 }
    /// Walking pace right now: an RPG gunner moves at half speed while reloading.
    var pace: Double { reloading ? kind.walkSpeed*0.5 : kind.walkSpeed }
}
/// A round in flight. Rockets fall under their own, weaker `gravity` and trail smoke.
/// A round with a `fuse` bursts on reaching that x even if it hit nothing, so cannon rounds
/// whose target was blasted away while they flew don't sail on past the strafed strip.
struct Shot { var position: Vec; var previous: Vec; var velocity: Vec; var life: Double = 0; var radius = World.bulletBlastRadius
    var gravity = World.gravity; var rocket = false; var fuse: Double? = nil }
struct Particle { var position: Vec; var velocity: Vec; var life: Double; var total: Double; var kind: Int; var size: Double }
struct Blast { var position: Vec; var age: Double = 0; var radius: Double }
/// Decorative wall panel drawn on a surviving rear wall.
struct Fixture { var x: Int; var y: Int; var w: Int; var h: Int }
/// Voxel bounds (inclusive) of an interior room or a window pane, used only for drawing.
struct CellRect { var x0: Int; var y0: Int; var x1: Int; var y1: Int }
/// Still water filling empty cells below `row` between two columns.
struct Pool { var x0: Int; var x1: Int; var row: Int }
struct Landmark { var name: String; var x: Double; var y: Double }

final class World {
    /// Voxels per layout unit along each axis. The map is laid out on an 8 px design
    /// grid; each design cell is subdivided into scale×scale voxels.
    static let scale = 2
    static let columns = 720*scale
    static let rows = 150*scale
    static let cell = 8.0/Double(scale)
    static let top = 104.0
    static let width = Double(columns)*cell
    static let bottom = top+Double(rows)*cell
    var voxels = [UInt8](repeating: 0, count: columns*rows)
    var onSound: ((SoundEvent) -> Void)?
    var chunks: [FallingChunk] = []
    // Rear panels remember the floor and ceiling cells that hold them up.
    var backdrops = [Int](repeating: -1, count: columns*rows)
    var ceilings = [Int](repeating: -1, count: columns*rows)
    var fixtures: [Fixture] = []
    // Drawing metadata: which room or window pane a cell belongs to (-1 for none).
    var rooms: [CellRect] = []
    var roomOf = [Int32](repeating: -1, count: columns*rows)
    var panes: [CellRect] = []
    var paneOf = [Int32](repeating: -1, count: columns*rows)
    var pools: [Pool] = []
    var landmarks: [Landmark] = []
    // Mission scoring: points each voxel pays when destroyed, objectives, and the running total.
    var worth = [UInt8](repeating: 0, count: columns*rows)
    /// Reinforced foundation cells: ground slabs, bridge piers, and the footings sunk beneath them.
    var footings = [Bool](repeating: false, count: columns*rows)
    /// Steel reinforcing bars cast inside concrete: 0 for none, otherwise the bar material
    /// (`barH` in slabs, `barV` in walls and columns) left standing where the concrete
    /// around it is blasted or burnt away. See `layRebar`.
    var rebar = [UInt8](repeating: 0, count: columns*rows)
    /// How strongly this level's buildings are reinforced; 1 is the first level, and later,
    /// harder levels raise it. Rebar concrete resists blasts, carries load, spans and leans
    /// further in proportion, and exposed bars hold more before they buckle.
    var reinforcement = 1.0
    var objectives: [Objective] = []
    var popups: [Popup] = []
    var score = 0
    var missionClock = 0.0
    var extracted = false
    /// Credits: the separate currency troops and support are bought with. Granted at the
    /// start of each round and never earned mid-round; points are only for extraction.
    var credits = 0
    /// Dev mode: purchases are free, support and RPGs never cool down, nothing is banked.
    var devMode = false
    /// Part of this round's credits paid out for the last round's points.
    var carriedCredits = 0
    /// Part of this round's credits withdrawn from the bank, after the transfer loss.
    var broughtCredits = 0
    /// Credits saved between rounds. Unspent credits are deposited on extraction and can be
    /// withdrawn in the lobby at a loss; the game view persists it through `onBankChange`.
    var bank = 0 { didSet { if bank != oldValue { onBankChange?(bank) } } }
    var onBankChange: ((Int) -> Void)?
    /// Credits deposited when this round was extracted; shown in the debrief.
    var banked = 0
    /// Credits spent on troops and support this round.
    var spent = 0
    /// Multiplier applied to fill/carve/room coordinates; reset() lays the map out in design units.
    var unit = 1
    var structureDirty = true
    var structureClock = 0.0
    var collapsed = 0
    /// Last id handed to a falling section; the renderer caches each section's texture by id.
    var chunkSerial = 0
    var soldiers: [Soldier] = []
    var crates: [SupplyCrate] = []
    var planes: [SupplyPlane] = []
    var jets: [StrafeJet] = []
    /// Height of the tallest block still standing; support aircraft fly well above it.
    var skyline = World.top
    /// Heading forced on support aircraft (+1 in from the west, -1 from the east), or nil to
    /// bring them in from the edge nearer the call-in point.
    var supportSide: Double?
    /// Seconds until `skyline` is measured again.
    var skylineClock = 0.0
    /// Seconds until another gun run can be called. Other support has no cooldown.
    var gunRunCooldown = 0.0
    /// Seconds until another firebomb run can be called.
    var firebombCooldown = 0.0
    var bombers: [FireBomber] = []
    var fireBombs: [FireBomb] = []
    var gelDrops: [GelDrop] = []
    var embers: [Ember] = []
    /// Every fire on the map; see `FireField`.
    var fire = FireField()
    /// Whether the current firebomb run's first canister has burst, for its status line.
    var bombed = false
    /// Set when fire shatters glass during a step, so the step plays one glass cue.
    var fireShattered = false
    static let muzzleSpeed = 780.0, gravity = 420.0
    var shots: [Shot] = []
    var particles: [Particle] = []
    var blasts: [Blast] = []
    var target: Vec? = nil
    var elapsed = 0.0
    var destroyed = 0
    var rounds = 0
    var nextID = 1
    var paused = false
    /// Game speed multiplier. Each frame runs `speed` fixed-size steps rather than one long
    /// step, so 2× and 4× play out exactly like 1× (same arcs, same collapses), only faster.
    var speed = 1
    static let speeds = [1,2,4]
    var shake = 0.0
    /// How much of an event at a world point (spanning `margin` world units around it) is on
    /// screen, from 0 (unseen) to 1 (fully in frame). Without a view everything counts as visible.
    var visibility: ((Vec, Double) -> Double)? = nil
    /// Kicks the camera in proportion to how much of the event at `p` is in view, capping the
    /// total at `cap`. Squaring the visible share keeps edge-of-frame destruction to a tremor.
    func quake(at p: Vec, _ amount: Double, cap: Double, margin: Double = 0) {
        let seen = min(1,max(0,visibility?(p,margin) ?? 1))
        guard seen > 0 else { return }
        shake = min(cap,shake+amount*seen*seen)
    }
    var status = "DEPLOY A SOLDIER TO BEGIN"
    var seed: UInt64 = 42
    var random: Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) & 0x7fffffff) / Double(0x7fffffff)
    }
    init() { reset() }
    func index(_ x: Int, _ y: Int) -> Int { y*Self.columns+x }
    func material(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0 && y >= 0 && x < Self.columns && y < Self.rows else { return 0 }
        return voxels[index(x,y)]
    }
    func material(at p: Vec) -> UInt8 {
        guard p.x >= 0 && p.y >= Self.top else { return 0 }
        return material(Int(p.x / Self.cell), Int((p.y-Self.top)/Self.cell))
    }
    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ m: UInt8) {
        let (x,y,w,h) = (x*unit,y*unit,w*unit,h*unit)
        guard w > 0 && h > 0 else { return }
        for row in max(0,y)..<min(Self.rows,y+h) {
            for col in max(0,x)..<min(Self.columns,x+w) { voxels[index(col,row)] = m; rebar[index(col,row)] = 0 }
        }
    }
    func carve(_ cx: Int, _ cy: Int, _ rx: Int, _ ry: Int) {
        let (cx,cy,rx,ry) = (cx*unit+unit/2,cy*unit+unit/2,rx*unit,ry*unit)
        for y in max(0,cy-ry)...min(Self.rows-1,cy+ry) {
            for x in max(0,cx-rx)...min(Self.columns-1,cx+rx) {
                let dx = Double(x-cx)/Double(rx), dy = Double(y-cy)/Double(ry)
                if dx*dx+dy*dy <= 1 { voxels[index(x,y)] = 0 }
            }
        }
    }
    func room(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, floor: Int, ceiling: Int) {
        let u = unit, id = Int32(rooms.count)
        rooms.append(CellRect(x0:x0*u,y0:y0*u,x1:(x1+1)*u-1,y1:(y1+1)*u-1))
        for y in y0*u..<(y1+1)*u {
            for x in x0*u..<(x1+1)*u { backdrops[index(x,y)] = index(x,floor*u); ceilings[index(x,y)] = index(x,ceiling*u+u-1); roomOf[index(x,y)] = id }
        }
    }
    /// Marks a rectangle as reinforced foundation: it resists blasts and carries double load.
    func reinforce(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        let (x,y,w,h) = (x*unit,y*unit,w*unit,h*unit)
        for row in max(0,y)..<min(Self.rows,y+h) {
            for col in max(0,x)..<min(Self.columns,x+w) { footings[index(col,row)] = true }
        }
    }
    /// The Kessel bridge, built from its own material (12) so troops treat it as a road
    /// rather than a building. A deck spans the gorge on two piers whose spread footings
    /// are sunk into the bedrock, abutments are cut into each bank, and graded ramps carry
    /// the approach road from the ground up to the deck.
    static let bridgeDeck = 57
    /// Floor of the Kessel gorge. The river over it is a ford shallow enough to wade, and
    /// the banks are graded within a soldier's step, so troops can still cross once the
    /// bridge is down.
    static let riverBed = 83
    /// Surface of the ford: two rows of water over the bed.
    static let riverSurface = riverBed-2
    func bridge() {
        let deck = Self.bridgeDeck, bed = Self.riverBed
        fill(252, deck, 76, 2, 12)
        for px in [280,298] {
            fill(px, deck+2, 3, bed-deck-2, 12)
            // Spread footing: wider than the pier and keyed three cells into the riverbed.
            fill(px-3, bed, 9, 3, 12)
            reinforce(px-3, bed-4, 9, 7)
        }
        // Abutments: solid seats under each end of the deck, buried in the bank.
        fill(252, deck+2, 10, 12, 12); reinforce(252, deck, 10, 14)
        fill(318, deck+2, 10, 12, 12); reinforce(318, deck, 10, 14)
        // Each end of the deck slopes down to the approach road, one or two voxels per
        // column, so troops walk up onto it instead of meeting a wall at head height.
        let u = unit, top = deck*u
        unit = 1
        for (end,inner) in [(252*u,260*u),(328*u-1,320*u)] {
            let dir = inner > end ? 1 : -1, outside = end-dir
            var ground = top
            while ground < Self.rows && !troopSolid(outside,ground) { ground += 1 }
            var col = end
            while col != inner {
                let surface = top+(ground-top)*abs(inner-col)/abs(inner-end+dir)
                for row in top..<ground {
                    let i = index(col,row)
                    if row < surface { if voxels[i] == 12 { voxels[i] = 0 } }
                    else if voxels[i] == 0 { voxels[i] = 12 }
                }
                col += dir
            }
        }
        unit = u
    }
    /// Concrete block of `floors` storeys standing on ground row `base`. Outer walls are
    /// three cells thick, interior columns keep slab spans and column loads within limits,
    /// and window panes hang beside a wall or column because glass carries no load.
    func building(_ x: Int, _ w: Int, _ floors: Int, _ base: Int, story: Int = 9, hut: Bool = true) {
        let roof = base-2-floors*story
        // Reinforced footing: a concrete mat sunk into the ground, wider than the
        // building, so shells must dig through it before the ground floor gives way.
        fill(x-2, base, w+4, 2, 3)
        reinforce(x-2, base-2, w+4, 4)
        for f in 0...floors { fill(x, base-2-f*story, w, 2, 3) }
        fill(x, roof, 3, base-roof, 3); fill(x+w-3, roof, 3, base-roof, 3)
        let bays = max(1, Int((Double(w-6)/16).rounded(.up)))
        var edges = [x+3]
        for b in 1..<max(2,bays) where b < bays {
            let cx = x+3+(w-6)*b/bays-1
            fill(cx, roof, 2, base-roof, 3); edges.append(cx+2)
        }
        for f in 0..<floors {
            let floor = base-2-f*story
            room(x+3, floor-story+2, x+w-4, floor-1, floor: floor, ceiling: floor-story+1)
            for e in edges { fill(e, floor-story+3, 4, story-5, 4) }
        }
        // Exterior trim: a projecting cornice, string courses at each upper floor,
        // corner parapets, and a stair hut with a steel mast on the roof.
        fill(x-1, roof, w+2, 1, 3)
        for f in 1..<max(1,floors) { fill(x-1, base-2-f*story, 1, 1, 3); fill(x+w, base-2-f*story, 1, 1, 3) }
        fill(x, roof-1, 2, 1, 3); fill(x+w-2, roof-1, 2, 1, 3)
        if hut && w >= 20 {
            let hut = x+w-10, u = unit
            fill(hut, roof-3, 6, 3, 3)
            unit = 1
            fill((hut+1)*u, (roof-9)*u, 1, 6*u, 11); fill((hut+1)*u-1, (roof-7)*u, 3, 1, 11)
            unit = u
        }
    }
    /// Groups glass into rectangular panes so windows can be drawn with frames and mullions.
    func findPanes() {
        panes = []; paneOf = [Int32](repeating: -1, count: Self.columns*Self.rows)
        for y in 0..<Self.rows {
            for x in 0..<Self.columns where voxels[index(x,y)] == 4 && paneOf[index(x,y)] < 0 {
                var x1 = x, y1 = y
                while x1+1 < Self.columns && voxels[index(x1+1,y)] == 4 && paneOf[index(x1+1,y)] < 0 { x1 += 1 }
                while y1+1 < Self.rows && (x...x1).allSatisfy({ voxels[index($0,y1+1)] == 4 && paneOf[index($0,y1+1)] < 0 }) { y1 += 1 }
                let id = Int32(panes.count)
                panes.append(CellRect(x0:x,y0:y,x1:x1,y1:y1))
                for py in y...y1 { for px in x...x1 { paneOf[index(px,py)] = id } }
            }
        }
    }
    func surfaceRow(_ x: Int) -> Int {
        if x < 180 { return 56 + Int(sin(Double(x)*0.052)*1.5) + (x > 145 ? Int(Double(x-145)*0.13) : 0) }
        // Keyframed profile: no-man's land, river gorge, town, factory, then the fortified ridge.
        // The embankments either side of the gorge rise flush with the bridge deck, so once
        // the span is down troops can still walk off the ends and down the banks.
        let deck = Self.bridgeDeck
        let keys = [(179,60),(206,60),(240,deck),(262,deck),(277,Self.riverBed),(303,Self.riverBed),(318,deck),(324,deck),(327,58),
                    (578,58),(600,47),(624,33),(694,33),(708,38),(719,41)]
        var row = 60.0
        for k in 1..<keys.count where x <= keys[k].0 {
            let a = keys[k-1], b = keys[k], t = Double(x-a.0)/Double(b.0-a.0)
            row = Double(a.1)+Double(b.1-a.1)*t; break
        }
        let rough = (x < 240 || (x > 578 && x < 624)) ? Int((sin(Double(x)*0.13)+sin(Double(x)*0.051))*0.8) : 0
        return Int(row.rounded())+rough
    }
    func reset() {
        onSound?(SoundEvent(cue:.reset))
        voxels = [UInt8](repeating: 0, count: Self.columns*Self.rows)
        chunks = []; collapsed = 0; structureDirty = true; structureClock = 0
        backdrops = [Int](repeating: -1, count: Self.columns*Self.rows)
        ceilings = [Int](repeating: -1, count: Self.columns*Self.rows)
        footings = [Bool](repeating: false, count: Self.columns*Self.rows)
        rebar = [UInt8](repeating: 0, count: Self.columns*Self.rows)
        rooms = []; roomOf = [Int32](repeating: -1, count: Self.columns*Self.rows)
        soldiers = []; shots = []; particles = []; blasts = []; crates = []; planes = []; jets = []; gunRunCooldown = 0; skylineClock = 0; supportSide = nil; target = nil
        resetFire()
        elapsed = 0; destroyed = 0; rounds = 0; nextID = 1; paused = false; speed = 1; seed = 42
        status = "PRESS E OR CLICK DEPLOY TO SPEND CREDITS ON TROOPS"
        let S = Self.scale
        for x in 0..<Self.columns {
            let surface = surfaceRow(x/S)*S
            for y in surface..<Self.rows {
                voxels[index(x,y)] = y > surface+10*S ? 2 : 1
            }
        }
        unit = S
        defer { unit = 1 }
        // Sector 1 · LZ Alpha and a small, fully voxel-built observation bunker.
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
        fill(156, 54, 6, 5, 7); fill(163, 55, 5, 5, 7)
        room(108, 36, 151, 45, floor: 46, ceiling: 36)
        room(108, 46, 151, 54, floor: 55, ceiling: 47)
        fixtures = [Fixture(x:127,y:49,w:6,h:4)]
        // Sector 2 · No-man's land: shell craters, a stepped trench, and a burnt-out tank.
        for (cx,r) in [(188,3),(199,2),(236,4)] { carve(cx, surfaceRow(cx)-1, r+1, r) }
        for i in 0..<18 { fill(209+i, surfaceRow(209+i), 1, min(3,i+1,18-i), 0) }
        fill(227, surfaceRow(227)-1, 4, 1, 6); fill(205, surfaceRow(205)-1, 3, 1, 6)
        let tank = surfaceRow(242)
        fill(240, tank-3, 13, 3, 11); fill(243, tank-5, 6, 2, 11); fill(249, tank-5, 7, 1, 11)
        // Sector 3 · River gorge spanned by a two-pier concrete bridge, laid after the
        // town so its east ramp meets the road beside the first building's footing.
        pools = [Pool(x0:262,x1:318,row:Self.riverSurface)]
        // Sector 4 · Ruined town: apartments, a church with a bell tower, a gutted block.
        building(330, 28, 3, 58)
        building(366, 20, 5, 58)
        building(394, 30, 2, 58, story:12)
        fill(424, 6, 8, 52, 5); fill(426, 10, 4, 6, 0); fill(427, 10, 2, 2, 11)
        for r in 0..<6 { fill(428-(r/2+1), r, (r/2+1)*2, 1, 5) }
        building(444, 26, 4, 58, hut:false)
        fill(458, 20, 12, 9, 0); fill(468, 19, 3, 2, 0)
        for (i,h) in [2,3,4,3,2,1].enumerated() { fill(471+i, 58-h, 1, h, 10) }
        fill(356, 56, 6, 2, 6); fill(386, 55, 4, 3, 7)
        fixtures += [Fixture(x:340,y:47,w:5,h:3),Fixture(x:404,y:41,w:6,h:4),Fixture(x:375,y:20,w:4,h:3)]
        bridge()
        // Sector 5 · Factory hall, chimney stack, and fuel tanks.
        building(488, 56, 1, 58, story:16)
        for k in 0..<3 { for r in 1...3 { fill(492+k*12+(r-1)*3, 40-r, 12-(r-1)*3, 1, 3) } }
        fill(548, 6, 5, 52, 5); fill(547, 6, 7, 2, 11); fill(547, 20, 7, 1, 11); fill(547, 34, 7, 1, 11)
        for cx in [557.5,569.5] {
            for y in 47...57 {
                for x in Int(cx)-5...Int(cx)+6 where pow(Double(x)-cx,2)+pow(Double(y)-52.5,2) <= 30 { fill(x,y,1,1,11) }
            }
        }
        fill(496, 52, 5, 4, 7); fill(506, 53, 4, 3, 7); fill(527, 52, 5, 4, 7)
        fixtures += [Fixture(x:514,y:44,w:8,h:4)]
        // Sector 6 · Ridge fortress, gun emplacement, and a concrete-lined tunnel depot.
        fill(586, surfaceRow(586)-1, 6, 1, 6)
        fill(612, surfaceRow(612)-1, 5, 1, 6)
        building(630, 34, 2, 33, story:8)
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
        room(604, 39, 696, 46, floor: 47, ceiling: 39)
        fill(630, 33, 34, 5, 3)
        fill(650, 43, 4, 4, 7); fill(655, 44, 4, 3, 7); fill(667, 45, 7, 2, 6)
        fixtures += [Fixture(x:623,y:42,w:6,h:3),Fixture(x:640,y:26,w:5,h:3)]
        layRebar()
        findPanes()
        fixtures = fixtures.map { Fixture(x:$0.x*S,y:$0.y*S,w:$0.w*S,h:$0.h*S) }
        pools = pools.map { Pool(x0:$0.x0*S,x1:$0.x1*S+S-1,row:$0.row*S) }
        landmarks = [Landmark(name:"LZ / ALPHA",x:112,y:602),
                     Landmark(name:"NO-MAN'S LAND",x:1590,y:500),Landmark(name:"KESSEL RIVER CROSSING",x:2100,y:500),
                     Landmark(name:"HOLLOWAY / RUINED TOWN",x:2660,y:200),Landmark(name:"WORKS NO. 4",x:3920,y:400),
                     Landmark(name:"RIDGE FORTRESS",x:5040,y:150),Landmark(name:"TUNNEL DEPOT",x:4900,y:470)]
        setupMission()
    }
    func ground(at x: Double) -> Double {
        let col = max(0,min(Self.columns-1,Int(x/Self.cell)))
        for y in 0..<Self.rows where material(col,y) != 0 { return Double(y)*Self.cell + Self.top }
        return Self.bottom
    }
    // MARK: Walking
    /// Troops only collide with terrain and bridge concrete; rubble and buildings sit on another layer.
    func troopSolid(_ x: Int, _ y: Int) -> Bool {
        let m = material(x,y)
        return m == 1 || m == 2 || m == 12
    }
    func troopSolid(at p: Vec) -> Bool {
        guard p.x >= 0 && p.y >= Self.top else { return false }
        return troopSolid(Int(p.x / Self.cell), Int((p.y-Self.top)/Self.cell))
    }
    func troopGround(at x: Double) -> Double {
        let col = max(0,min(Self.columns-1,Int(x/Self.cell)))
        for y in 0..<Self.rows where troopSolid(col,y) { return Double(y)*Self.cell + Self.top }
        return Self.bottom
    }
    /// Body height in cells that a standing soldier needs clear.
    static let bodyCells = 6
    /// Tallest step, in cells, a soldier scrambles up: anything no taller than the soldier.
    static let climbCells = bodyCells
    func bodyBlocked(x: Double, y: Double, sign: Double) -> Bool {
        var h = 1.0
        while h < Soldier.height {
            if troopSolid(at:Vec(x:x+sign*5,y:y-h)) || troopSolid(at:Vec(x:x,y:y-h)) { return true }
            h += Self.cell
        }
        return false
    }
    /// A standing spot: feet in empty cell (c,r) on solid ground with room for the body, and
    /// not pressed against a wall too tall to climb (a climbable step beside it is fine).
    func standable(_ c: Int, _ r: Int) -> Bool {
        guard c >= 1 && c < Self.columns-1 && r >= Self.climbCells && r+1 < Self.rows, troopSolid(c,r+1) else { return false }
        for k in 0..<Self.bodyCells where troopSolid(c,r-k) { return false }
        return !troopSolid(c-1,r-Self.climbCells) && !troopSolid(c+1,r-Self.climbCells)
    }
    /// Breadth-first search over standing spots: step up `climbCells`, drop any distance.
    /// Returns the columns to walk through to the reachable spot nearest `goalX`.
    func plan(from p: Vec, to goalX: Double) -> [Int] {
        let cols = Self.columns, goal = max(1,min(cols-2,Int(goalX/Self.cell)))
        let sr = Int((p.y+1-Self.top)/Self.cell)-1, sc = max(1,min(cols-2,Int(p.x/Self.cell)))
        guard sr >= 0 else { return [] }
        let start = sr*cols+sc
        var parent: [Int:Int] = [start:-1]
        var queue = [start], head = 0, best = start
        func closer(_ a: Int, _ b: Int) -> Bool { abs(a%cols-goal) < abs(b%cols-goal) }
        while head < queue.count {
            let n = queue[head]; head += 1
            if closer(n,best) { best = n }
            if n%cols == goal { best = n; break }
            let c = n%cols, r = n/cols
            for dir in [-1,1] {
                let nc = c+dir
                guard nc >= 1 && nc < cols-1, !troopSolid(nc,r-Self.bodyCells) else { continue }
                var rr = r-Self.climbCells
                while rr <= r+30 && rr+1 < Self.rows {
                    // Climbing lifts the body above its current spot, so that column needs the headroom too.
                    if standable(nc,rr) && (rr..<max(rr,r)).allSatisfy({ !troopSolid(c,$0-Self.bodyCells+1) }) { let m = rr*cols+nc; if parent[m] == nil { parent[m] = n; queue.append(m) }; break }
                    if troopSolid(nc,rr) { break }
                    rr += 1
                }
            }
        }
        var path: [Int] = [], n = best
        while n != start && n >= 0 { path.append(n%cols); n = parent[n] ?? -1 }
        return path.reversed()
    }
    /// Gap between neighbours in a line formation; idle troops edge apart until this far from each other.
    static let formationSpacing = 12.0
    /// Offset of rank `k` of `n` in a line formation centred on its rally point.
    static func formationOffset(_ k: Int, of n: Int) -> Double { (Double(k)-Double(n-1)/2)*formationSpacing }
    /// Adds soldiers in a line at the landing zone, or around `x` when given. Free: purchases go through `purchase`.
    func spawn(_ count: Int, kind: TroopKind = .rifleman, at x: Double? = nil) {
        let n = count
        let centre = x ?? 128 + random*145
        for k in 0..<n {
            let px = min(Self.deployZone.upperBound,max(Self.deployZone.lowerBound,centre+Self.formationOffset(k,of:n)))
            soldiers.append(Soldier(id: nextID, position: Vec(x:px,y:troopGround(at:px)), kind: kind, cooldown:random*0.7, ammo: kind.magazine))
            nextID += 1
        }
        onSound?(SoundEvent(cue:.deploy))
        status = "UNIT DEPLOYED · CLICK A STRUCTURE TO ATTACK"
    }
    /// A left click on the map. A selection of RPG gunners alone fires at `p`; otherwise the
    /// auto-aimed troops in it attack `p`, and any RPG gunners mixed in hold fire.
    func attack(_ p: Vec) {
        guard soldiers.contains(where: {$0.selected}) else { status = "SELECT OR DEPLOY A SOLDIER FIRST"; return }
        if rocketsSelected { fireRockets(at:p); return }
        onSound?(SoundEvent(cue:.order,x:p.x))
        target = p
        for i in soldiers.indices where soldiers[i].selected && !soldiers[i].kind.manualAim { soldiers[i].target = p; soldiers[i].moveX = nil }
        status = "ATTACK ORDER · TARGET LOCKED"
    }
    /// True when something is selected and every selected soldier is an RPG gunner: only then
    /// do clicks fire rockets and their aim lines show.
    var rocketsSelected: Bool {
        soldiers.contains { $0.selected } && soldiers.allSatisfy { !$0.selected || $0.kind.manualAim }
    }
    static let rocketSpeed = 880.0
    /// Rockets are under thrust, so they sag far less than shells but still drop with range.
    static let rocketGravity = 120.0
    /// Muzzle and launch velocity of a rocket `s` would fire at the pointer `aim`: straight
    /// toward it at `rocketSpeed`, then falling under `rocketGravity`, so it drops below the
    /// pointer at range and the player must aim high.
    func rocketLaunch(_ s: Soldier, at aim: Vec) -> (origin: Vec, velocity: Vec) {
        var aimed = s; aimed.facing = aim.x >= s.position.x ? 1 : -1
        let origin = aimed.muzzleOrigin
        let dx = aim.x-origin.x, dy = aim.y-origin.y, d = max(1,hypot(dx,dy))
        return (origin,Vec(x:dx/d*Self.rocketSpeed,y:dy/d*Self.rocketSpeed))
    }
    /// Predicted flight of the rocket `s` would fire at `aim`, or nil with none left.
    func rocketTrajectory(of s: Soldier, at aim: Vec) -> [Vec]? {
        guard s.kind.manualAim, !s.outOfAmmo else { return nil }
        let (origin,velocity) = rocketLaunch(s,at:aim)
        return trajectory(from:origin,velocity:velocity,gravity:Self.rocketGravity)
    }
    /// Fires one rocket from every selected RPG gunner that is loaded, along the path
    /// `rocketTrajectory` previews. Returns how many rockets left.
    @discardableResult func fireRockets(at aim: Vec) -> Int {
        var fired = 0, reloading = 0, empty = 0
        for i in soldiers.indices where soldiers[i].selected && soldiers[i].kind.manualAim {
            var s = soldiers[i]
            if s.outOfAmmo { empty += 1; continue }
            if s.cooldown > 0 { reloading += 1; continue }
            let (origin,velocity) = rocketLaunch(s,at:aim)
            s.facing = aim.x >= s.position.x ? 1 : -1
            onSound?(SoundEvent(cue:.shot,x:origin.x))
            shots.append(Shot(position:origin,previous:origin,velocity:velocity,radius:s.kind.blastRadius,gravity:Self.rocketGravity,rocket:true))
            // Backblast out of the rear of the tube.
            for _ in 0..<6 {
                particles.append(Particle(position:origin+Vec(x:-velocity.x,y:-velocity.y)*0.04,velocity:Vec(x:-velocity.x*0.15+(random-0.5)*50,y:-velocity.y*0.15+(random-0.5)*50),life:0.6+random*0.6,total:1.5,kind:9,size:6+random*8))
            }
            s.cooldown = devMode ? 0 : s.kind.reload; s.flash = 0.12; s.ammo -= 1; rounds += 1
            soldiers[i] = s; fired += 1
        }
        if fired > 0 {
            status = fired == 1 ? "ROCKET AWAY" : "\(fired) ROCKETS AWAY"
            if soldiers.contains(where:{ $0.selected && $0.kind.manualAim && $0.outOfAmmo }) { status += " · RPG OUT OF AMMO · [Q] CALL A SUPPLY CRATE" }
        } else if reloading > 0 {
            status = "RPG RELOADING"
            onSound?(SoundEvent(cue:.cease))
        } else if empty > 0 {
            status = "RPG OUT OF AMMO · [Q] CALL A SUPPLY CRATE"
            onSound?(SoundEvent(cue:.cease))
        }
        return fired
    }
    /// Idle RPG gunners in the selection turn to face where the player is aiming.
    func faceRockets(toward aim: Vec) {
        guard rocketsSelected else { return }
        for i in soldiers.indices where soldiers[i].selected && soldiers[i].moveX == nil && abs(aim.x-soldiers[i].position.x) > 2 {
            soldiers[i].facing = aim.x > soldiers[i].position.x ? 1 : -1
        }
    }
    func move(_ x: Double) {
        guard soldiers.contains(where:{$0.selected}) else { return }
        onSound?(SoundEvent(cue:.order,x:x))
        // Each soldier takes a slot in a line around the rally point, keeping its left-to-right order so paths don't cross.
        let squad = soldiers.indices.filter{soldiers[$0].selected}.sorted{(soldiers[$0].position.x,soldiers[$0].id) < (soldiers[$1].position.x,soldiers[$1].id)}
        for (k,i) in squad.enumerated() {
            soldiers[i].moveX = max(32,min(Self.width-40,x+Self.formationOffset(k,of:squad.count))); soldiers[i].target = nil; soldiers[i].route = []; soldiers[i].routed = false; soldiers[i].stuck = 0
        }
        target = nil
        status = "MOVE ORDER · ADVANCING TO RALLY POINT"
    }
    func cease() {
        onSound?(SoundEvent(cue:.cease))
        for i in soldiers.indices { soldiers[i].target = nil; soldiers[i].moveX = nil }
        target = nil; status = "CEASE FIRE · AWAITING ORDERS"
    }
    /// Fixed muzzle speed: aim the low arc onto `aim`, or lob at 45° when it is out of reach.
    static func launch(from origin: Vec, to aim: Vec, speed: Double = muzzleSpeed) -> Vec {
        let dx = aim.x-origin.x, dy = aim.y-origin.y
        let v = speed, g = gravity, dir = dx >= 0 ? 1.0 : -1.0
        let ax = abs(dx), disc = v*v*v*v-g*(g*ax*ax-2*dy*v*v)
        let angle = disc >= 0 && ax > 1 ? atan((v*v-disc.squareRoot())/(g*ax)) : Double.pi/4
        return Vec(x:dir*v*cos(angle),y:-v*sin(angle))
    }
    /// Predicted flight of a round, one point per 60 Hz frame, integrated like `shots` and
    /// ending where it would first hit a block, a map edge, or the bottom. Ignores aim spread.
    func trajectory(from origin: Vec, velocity: Vec, gravity: Double = World.gravity, maxTime: Double = 6) -> [Vec] {
        let dt = 1.0/60
        var p = origin, v = velocity, points = [origin]
        for _ in 0..<Int(maxTime/dt) {
            let steps = max(1,Int(hypot(v.x,v.y)*dt/3)+1)
            for _ in 0..<steps {
                let sub = dt/Double(steps)
                v.y += gravity*sub
                p = p+v*sub
                if p.x < 0 || p.x > Self.width || material(at:p) != 0 || p.y >= Self.bottom { points.append(p); return points }
            }
            points.append(p)
        }
        return points
    }
    /// Predicted path of a soldier's next round at its attack target, or nil without one
    /// (or without a round to fire).
    func trajectory(of s: Soldier) -> [Vec]? {
        guard let aim = s.target, !s.outOfAmmo else { return nil }
        var aimed = s; aimed.facing = aim.x > s.position.x ? 1 : -1
        return trajectory(from:aimed.muzzleOrigin,velocity:Self.launch(from:aimed.muzzleOrigin,to:aim))
    }
    /// Idle soldiers standing on the same level edge away from neighbours closer than
    /// `formationSpacing`, so a pile of troops relaxes into a line. They never step off a ledge.
    func spread(_ s: inout Soldier, _ i: Int, _ dt: Double) {
        guard s.falling == 0 else { return }
        var push = 0.0
        for (j,o) in soldiers.enumerated() where j != i && abs(o.position.y-s.position.y) < Soldier.height/2 {
            let dx = s.position.x-o.position.x
            guard abs(dx) < Self.formationSpacing else { continue }
            push += (Self.formationSpacing-abs(dx))*(dx != 0 ? (dx > 0 ? 1 : -1) : (s.id > o.id ? 1 : -1))
        }
        guard abs(push) > 0.5 else { return }
        let sign = push > 0 ? 1.0 : -1.0
        let next = s.position.x+sign*min(s.pace*0.5*dt,abs(push))
        guard next > 32 && next < Self.width-40, !bodyBlocked(x:next,y:s.position.y,sign:sign),
              troopSolid(at:Vec(x:next,y:s.position.y+1)) || troopSolid(at:Vec(x:next,y:s.position.y+1+Self.cell)) else { return }
        s.position.x = next; s.stride += dt*5*s.pace/46
        if s.target == nil { s.facing = sign }
    }
    /// Rifle rounds chip one to three voxels; levelling buildings is the grenadiers' job.
    static let bulletBlastRadius = 3.8
    /// Blasts reach this much further into loose rubble, so a rifle round clears three to six voxels.
    static let rubbleReach = 2.0
    func explode(at p: Vec, radius: Double = 29) {
        onSound?(SoundEvent(cue:.explosion,x:p.x))
        var brokeGlass = false, gained = 0
        structureDirty = true
        let c = Self.cell
        let px = Int(p.x/c), py = Int((p.y-Self.top)/c), reach = Int(radius*1.2/c)+1
        if px+reach >= 0 && py+reach >= 0 && px-reach < Self.columns && py-reach < Self.rows {
            for y in max(0,py-reach)...min(Self.rows-1,py+reach) {
                for x in max(0,px-reach)...min(Self.columns-1,px+reach) where backdrops[index(x,y)] >= 0 {
                    if hypot(Double(x)*c+c/2-p.x,Double(y)*c+Self.top+c/2-p.y) < radius*1.2 { backdrops[index(x,y)] = -1 }
                }
            }
        }
        blasts.append(Blast(position:p,radius:radius))
        quake(at:p,2*radius/29,cap:5,margin:radius)
        let cx = Int(p.x/c), cy = Int((p.y-Self.top)/c), range = Int(radius*Self.rubbleReach/c)+1
        for y in max(0,cy-range)..<max(0,min(Self.rows,cy+range+1)) {
            for x in max(0,cx-range)..<max(0,min(Self.columns,cx+range+1)) {
                let m = material(x,y)
                guard m != 0 else { continue }
                let pos = Vec(x:Double(x)*c+c/2,y:Double(y)*c+Self.top+c/2)
                let distance = hypot(pos.x-p.x,pos.y-p.y)
                // Ground resists blasts so shells leave shallow dents rather than pits soldiers must cross.
                // Reinforced footings and bridge concrete shrug off part of each blast; loose rubble scatters easily.
                let i = index(x,y), footing = (m == 3 || m == 12) && footings[i]
                // Rebar concrete shrugs off more of the blast the better the level reinforces it,
                // and exposed bars only part in the heart of a blast.
                let bars = m == 3 && rebar[i] != 0
                let resist = m == 1 ? 0.5 : m == 2 ? 0.36 : footing ? 0.6 : bars ? 1/(1+0.2*reinforcement) : m == 12 ? 0.8 : m == 10 ? Self.rubbleReach : Self.isBar(m) ? 0.5 : 1.0
                if distance < radius*resist {
                    if m == 4 { brokeGlass = true }
                    gained += claim(i)
                    // Concrete blown off its bars leaves them standing, bent but still holding.
                    let exposed = bars && distance > radius*0.35
                    voxels[i] = exposed ? rebar[i] : 0; destroyed += 1
                    if exposed { worth[i] = Self.points(rebar[i]) }
                    particles.append(Particle(position:pos,velocity:Vec(x:(random-0.5)*200,y:-random*180-30),life:1.0+random,total:2,kind:Self.isBar(m) ? 11 : Int(m),size:1.5+random*2))
                }
            }
        }
        if brokeGlass { onSound?(SoundEvent(cue:.glass,x:p.x)) }
        award(gained,at:p)
        for _ in 0..<16 {
            particles.append(Particle(position:p,velocity:Vec(x:(random-0.5)*230,y:(random-0.75)*220),life:0.4+random*0.6,total:1,kind:8,size:1.5+random*2))
        }
        for _ in 0..<8 {
            particles.append(Particle(position:p,velocity:Vec(x:(random-0.5)*45,y:-random*40-15),life:1.5+random,total:2.5,kind:9,size:9+random*14))
        }
    }
    /// Advances one real-time frame at the current game speed.
    func advance(_ dt: Double) {
        for _ in 0..<speed { update(dt) }
    }
    /// Steps to the next speed in `speeds`, wrapping from 4× back to 1×.
    func cycleSpeed() {
        speed = Self.speeds[((Self.speeds.firstIndex(of:speed) ?? 0)+1) % Self.speeds.count]
    }
    func update(_ dt: Double) {
        guard !paused else { return }
        elapsed += dt
        structureClock += dt
        if structureDirty && structureClock >= 0.12 {
            structureClock = 0; structureDirty = false; solveStructure()
        }
        updateChunks(dt)
        updateMission(dt)
        shake = max(0,shake-dt*12)
        for i in soldiers.indices {
            soldiers[i].cooldown -= dt; soldiers[i].flash = max(0,soldiers[i].flash-dt); soldiers[i].rearmed = max(0,soldiers[i].rearmed-dt)
            var s = soldiers[i]
            // Feet settle onto surviving voxels, including crater floors.
            if !troopSolid(at:Vec(x:s.position.x,y:s.position.y+1)) {
                s.falling += 400*dt
                let nextY = min(Self.bottom-6,s.position.y+s.falling*dt)
                var y = s.position.y
                while y < nextY && !troopSolid(at:Vec(x:s.position.x,y:y+1)) { y += 1 }
                s.position.y = min(y,Self.bottom-6)
            } else { s.falling = 0 }
            if let goal = s.moveX, abs(goal-s.position.x) > 4 {
                if !s.routed {
                    s.route = plan(from:s.position,to:goal); s.routed = true
                    if s.route.isEmpty { s.moveX = nil }
                }
                if let col = s.route.first {
                    let wx = (Double(col)+0.5)*Self.cell
                    if abs(wx-s.position.x) < 2 { s.route.removeFirst(); if s.route.isEmpty { s.moveX = nil } }
                    else {
                        let sign = wx > s.position.x ? 1.0 : -1.0
                        let next = s.position.x+sign*min(s.pace*dt,abs(wx-s.position.x))
                        // Scramble up ledges and rubble piles as tall as the soldier. The body test
                        // looks 5 px ahead, up to two route columns, so allow two planned steps.
                        var y = s.position.y, lift = 0.0
                        while lift < Double(2*Self.climbCells)*Self.cell && bodyBlocked(x:next,y:y,sign:sign) { y -= Self.cell; lift += Self.cell }
                        if bodyBlocked(x:next,y:y,sign:sign) {
                            // Terrain changed under the route (new rubble): plan again, give up if still jammed.
                            s.stuck += dt; s.routed = false
                            if s.stuck > 1.5 { s.moveX = nil }
                        } else {
                            s.stuck = 0; s.position = Vec(x:next,y:y); s.facing = sign
                            // Gait cadence scales with pace so footsteps keep time with the feet.
                            let step = dt*10*s.pace/46; s.stride += step
                            if Int(s.stride / .pi) != Int((s.stride-step) / .pi) { onSound?(SoundEvent(cue:.step,x:s.position.x)) }
                        }
                    }
                } else { s.moveX = nil }
            } else { s.moveX = nil; spread(&s,i,dt) }
            if let aim = s.target, s.cooldown <= 0, !s.outOfAmmo {
                s.facing = aim.x > s.position.x ? 1 : -1
                let origin = s.muzzleOrigin
                let velocity = Self.launch(from:origin,to:Vec(x:aim.x+(random-0.5)*13,y:aim.y))
                onSound?(SoundEvent(cue:.shot,x:origin.x))
                shots.append(Shot(position:origin,previous:origin,velocity:velocity,radius:s.kind.blastRadius))
                s.cooldown = s.kind.reload+random*0.5; s.flash = 0.09; rounds += 1
                s.ammo -= 1
                if s.outOfAmmo { status = "\(s.kind.name) OUT OF AMMO · [Q] CALL A SUPPLY CRATE" }
            }
            soldiers[i] = s
        }
        var remaining: [Shot] = []
        for var shot in shots {
            shot.life += dt
            shot.previous = shot.position
            let steps = max(1,Int(hypot(shot.velocity.x,shot.velocity.y)*dt/3)+1)
            var hit = false
            for _ in 0..<steps {
                let sub = dt/Double(steps)
                shot.velocity.y += shot.gravity*sub
                shot.position = shot.position+shot.velocity*sub
                if shot.position.x < 0 || shot.position.x > Self.width { shot.position.x = min(max(shot.position.x,0),Self.width); shot.velocity.x = 0 }
                if material(at:shot.position) != 0 || shot.position.y >= Self.bottom { hit = true; break }
                if let fuse = shot.fuse, (shot.position.x-fuse)*shot.velocity.x >= 0 && (shot.previous.x-fuse)*shot.velocity.x < 0 { hit = true; break }
            }
            if shot.rocket && !hit {
                particles.append(Particle(position:shot.previous,velocity:Vec(x:(random-0.5)*16,y:(random-0.5)*16-8),life:0.7+random*0.5,total:1.4,kind:9,size:4+random*4))
            }
            if hit { explode(at:shot.position,radius:shot.radius) } else { remaining.append(shot) }
        }
        shots = remaining
        updateSupport(dt)
        updateFire(dt)
        for i in particles.indices {
            particles[i].life -= dt
            // Smoke (9) and fire soot (14) drift; soot billows as it rises.
            if particles[i].kind == 14 { particles[i].size += 3*dt; particles[i].velocity.y *= exp(-0.15*dt) }
            else if particles[i].kind != 9 { particles[i].velocity.y += 280*dt }
            particles[i].position = particles[i].position+particles[i].velocity*dt
        }
        particles.removeAll { $0.life <= 0 || $0.position.y > Self.bottom+2 }
        if particles.count > 3000 { particles.removeFirst(particles.count-3000) }
        for i in blasts.indices { blasts[i].age += dt }
        blasts.removeAll { $0.age > 0.45 }
    }
}
