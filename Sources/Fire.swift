import Foundation

/// A napalm canister in free fall. It leaves the bomber's ramp at the plane's speed and drops
/// under gravity. Like a real incendiary it punches through up to `World.firebombPierce`
/// blocks of roof, wall, or trim until it breaks into a room, and bursts on the next thing
/// it hits, so the gel lands inside the building. Ground stops it at once.
struct FireBomb {
    var position: Vec
    var previous: Vec
    var velocity: Vec
    var pierce = World.firebombPierce
    /// Set once it has broken through into a room.
    var through = false
}
/// A gobbet of burning gel thrown out by a bursting canister. It sticks in the open cell in
/// front of the first block it touches and keeps burning there.
struct GelDrop { var position: Vec; var velocity: Vec; var life: Double }
/// A glowing brand lofted out of a strong fire. Where it comes down on something that burns
/// (a room's contents, a crate, a sandbag) it can start a spot fire.
struct Ember { var position: Vec; var velocity: Vec; var life: Double }
/// A C-130 on a firebombing pass. It crosses from the map edge nearer the target at the
/// supply plane's height and rolls one canister off its ramp for each aim point, timed so
/// each lands on its point.
struct FireBomber {
    var x: Double
    /// Current height; it follows `World.transportAltitude` as the skyline changes.
    var y: Double
    /// Ground points the stick is laid across, in the order the plane passes over them.
    let aims: [Double]
    /// +1 flying east (in from the west edge), -1 flying west (in from the east edge).
    var heading = 1.0
    var released = 0
    var done: Bool { released >= aims.count }
}

/// Fire state for every cell of the voxel grid.
///
/// The model is a heat-transfer cellular automaton run at `World.fireStep`:
/// * A cell burns while it has fuel: its own (the contents of a room, a timber crate, hessian
///   sandbags) and any napalm gel resting in it. Intensity rises toward what the fuel and the
///   air around it can sustain and falls back as the fuel runs out, so every fire dies out.
/// * Burning cells pass heat to their neighbours, most strongly upward (flames and hot gas
///   rise), less to the sides, and little downward. Gel also scorches whatever it clings to.
/// * Fuel ignites once it has soaked up its ignition point; heat leaks away when the fire
///   next to it moves on, so a passing flicker does not light everything.
/// * Concrete, brick, steel, glass and rubble do not burn but are weakened by the heat they
///   absorb, and spall, buckle or shatter once it passes their toughness. That damage scores
///   like any other and feeds the structural solver, so a long fire can bring a floor down.
/// * Gel with nothing to cling to runs down until it lands on something.
struct FireField {
    static var count: Int { World.columns*World.rows }
    /// Flame intensity, 0 (out) to 1 (fully involved).
    var flame = [Float](repeating:0,count:count)
    /// Seconds of full-intensity burning left in a cell's own fuel; -1 until it is first needed.
    var fuel = [Float](repeating:-1,count:count)
    /// Napalm gel in a cell, in seconds of full-intensity burning.
    var gel = [Float](repeating:0,count:count)
    /// Heat soaked up by fuel that is not burning yet.
    var heat = [Float](repeating:0,count:count)
    /// Heat absorbed by blocks that cannot burn; they fail at their toughness.
    var scorch = [Float](repeating:0,count:count)
    /// Soot for drawing, 0 (clean) to 3 (burnt out).
    var char = [UInt8](repeating:0,count:count)
    /// Whether a cell is in `burning`.
    var listed = [Bool](repeating:false,count:count)
    var burning: [Int] = []
    /// Cells holding heat, so it can leak away.
    var warm: [Int] = []
    var clock = 0.0
}

extension World {
    static let firebombCount = 8
    /// Gap between the canisters' aim points; the stick covers about 450 px.
    static let firebombSpacing = 64.0
    /// Seconds before another firebomb run can be called, counted from the call-in.
    static let firebombCooldown = 90.0
    /// Canisters leave the ramp at the plane's speed with a slight downward push.
    static func firebombRelease(_ heading: Double) -> Vec { Vec(x:heading*planeSpeed,y:30) }
    static let gelDropsPerBomb = 44
    /// Blocks of building a canister can punch through before it bursts.
    static let firebombPierce = 10
    /// Gel in each splashed gobbet and in the pool around the impact, in seconds of burning.
    static let gelPerDrop: Float = 45, gelPool: Float = 60
    /// Most gel one cell holds; gel running into a full cell spreads too thin to matter.
    static let gelLimit: Float = 90
    /// Pool half-width in cells either side of the impact.
    static let gelPoolReach = 7
    /// Seconds between fire simulation steps.
    static let fireStep = 0.1
    /// Most cells that may burn at once; further ignitions wait for room.
    static let maxFires = 14_000
    static let maxEmbers = 40
    /// Heat passed per second by a full-intensity flame to the cell at (dx,dy). Up is negative y.
    /// The (0,-2) entry is the hot plume, which only reaches past an open cell.
    static let heatSpread: [(dx: Int, dy: Int, w: Float)] = [(0,-1,1.0),(-1,-1,0.45),(1,-1,0.45),(-1,0,0.4),(1,0,0.4),
                                                             (-1,1,0.12),(1,1,0.12),(0,1,0.1),(0,-2,0.5)]
    /// Extra heat per second that burning gel puts into each block it touches.
    static let gelContact: Float = 4
    /// Share of held heat that leaks away per second.
    static let heatLoss: Float = 0.3

    /// Where each canister of a stick centred on `x` is aimed.
    static func firebombAims(_ x: Double) -> [Double] {
        (0..<firebombCount).map { min(width-4,max(4,x+(Double($0)-Double(firebombCount-1)/2)*firebombSpacing)) }
    }
    /// How far short of `aim` a canister released from a plane at height `altitude` must
    /// leave the ramp to land on it.
    func bombLead(_ aim: Double, from altitude: Double) -> Double {
        let drop = max(20,ground(at:aim)-altitude-14), v = Self.firebombRelease(1).y, g = Self.gravity
        return Self.planeSpeed*(-v+(v*v+2*g*drop).squareRoot())/g
    }

    // MARK: Fuel and materials
    /// Fuel that burns where it stands: furnishings in a room, timber crates, sandbags.
    func selfBurnable(_ i: Int) -> Bool {
        let m = voxels[i]
        return m == 7 || m == 6 || (m == 0 && backdrops[i] >= 0)
    }
    /// A cell's own fuel left, in seconds of full-intensity burning.
    func ownFuel(_ i: Int) -> Float {
        guard selfBurnable(i) else { return 0 }
        if fire.fuel[i] < 0 {
            switch voxels[i] {
            case 7: fire.fuel[i] = 45
            case 6: fire.fuel[i] = 12
            default:
                // Furniture stands on the floor; the upper part of a room holds less to burn.
                let above = backdrops[i]/Self.columns-i/Self.columns
                fire.fuel[i] = above <= 3*Self.scale ? 50 : 22
            }
        }
        return fire.fuel[i]
    }
    func ignitionPoint(_ i: Int) -> Float {
        switch voxels[i] { case 7: return 1.6; case 6: return 2.4; default: return 0.9 }
    }
    /// Heat a block that cannot burn absorbs before it fails; nil for blocks fire cannot harm.
    static func heatToughness(_ m: UInt8) -> Float? {
        switch m {
        case 4: return 1.2     // glass shatters
        case 11, 13, 14: return 18  // steel and rebar lose their strength
        case 10: return 15     // loose rubble crumbles
        case 5: return 27      // brick
        case 3: return 33      // concrete spalls
        case 12: return 54     // bridge concrete
        default: return nil
        }
    }
    /// Per-block spread of toughness, 0.5 to 1.5, so fire damage is patchy rather than layered.
    static func toughnessSpread(_ i: Int) -> Float { 0.5+Float((i &* 2654435761) & 1023)/1023 }

    // MARK: Igniting
    /// Sets a cell burning at no less than `intensity`. Returns false if it could not be lit.
    @discardableResult func ignite(_ i: Int, _ intensity: Float) -> Bool {
        if !fire.listed[i] {
            guard fire.burning.count < Self.maxFires else { return false }
            fire.listed[i] = true; fire.burning.append(i)
        }
        fire.flame[i] = max(fire.flame[i],intensity)
        return true
    }
    /// Lays burning napalm gel in an open cell.
    func addGel(_ i: Int, _ amount: Float) {
        guard i >= 0 && i < voxels.count && voxels[i] == 0 else { return }
        fire.gel[i] = min(Self.gelLimit,fire.gel[i]+amount)
        ignite(i,0.9)
    }
    /// Puts heat into a cell: fuel moves toward ignition, everything else toward failure.
    func heatCell(_ n: Int, _ amount: Float) {
        guard fire.flame[n] <= 0 else { return }
        // Nothing under water catches, and soaked fuel has to steam dry first.
        guard water.mass[n] < 0.25 else { return }
        let m = voxels[n]
        if let tough = Self.heatToughness(m) {
            fire.scorch[n] += amount
            let limit = tough*Self.toughnessSpread(n)*(footings[n] ? 2 : 1)
            if fire.scorch[n] >= limit { burnAway(n) }
            else { fire.char[n] = max(fire.char[n],UInt8(min(2,fire.scorch[n]/limit*3))) }
            return
        }
        guard selfBurnable(n), ownFuel(n) > 0 else { return }
        if fire.heat[n] == 0 { fire.warm.append(n) }
        fire.heat[n] += amount*(1-0.85*water.soak[n])
        if fire.heat[n] >= ignitionPoint(n) { ignite(n,0.15) }
    }
    /// Removes a block destroyed by fire, scoring it like a blasted one.
    func burnAway(_ i: Int) {
        let m = voxels[i]
        guard m != 0 else { return }
        let p = Vec(x:(Double(i%Self.columns)+0.5)*Self.cell,y:(Double(i/Self.columns)+0.5)*Self.cell+Self.top)
        award(claim(i),at:p)
        // Spalled concrete bares its reinforcing bars.
        voxels[i] = m == 3 ? rebar[i] : 0; destroyed += 1; structureDirty = true
        if voxels[i] != 0 { worth[i] = Self.points(voxels[i]) }
        if m == 3 { reanchor(i) }
        fire.scorch[i] = 0; fire.char[i] = 0; fire.fuel[i] = -1; fire.heat[i] = 0
        if m == 4 { fireShattered = true }
        if random < 0.4 {
            particles.append(Particle(position:p,velocity:Vec(x:(random-0.5)*40,y:-random*30),life:0.8+random,total:2,kind:Int(m),size:1.5+random*1.5))
        }
    }

    /// Rear panels hang between the face of a floor slab and the face of the ceiling slab.
    /// When fire spalls that face off, panels in the column re-anchor to the next layer of
    /// the slab, so a room keeps its rear wall until a slab is actually burnt through.
    func reanchor(_ i: Int) {
        let cols = Self.columns
        var k = i+cols
        if i >= cols && voxels[i-cols] == 3 {
            while k < voxels.count && ceilings[k] == i { ceilings[k] = i-cols; k += cols }
        }
        k = i-cols
        if i+cols < voxels.count && voxels[i+cols] == 3 {
            while k >= 0 && backdrops[k] == i { backdrops[k] = i+cols; k -= cols }
        }
    }

    // MARK: Simulation
    /// Advances the firebombers, canisters, gel, embers, and every fire by one frame.
    func updateFire(_ dt: Double) {
        updateBombers(dt)
        updateGel(dt)
        updateEmbers(dt)
        fire.clock += dt
        if fire.clock >= Self.fireStep {
            fire.clock -= Self.fireStep
            stepFire(Float(Self.fireStep))
        }
    }
    func updateBombers(_ dt: Double) {
        for b in bombers.indices {
            let h = bombers[b].heading
            bombers[b].x += h*Self.planeSpeed*dt
            bombers[b].y = towardCruise(bombers[b].y,dt)
            let ramp = bombers[b].x-h*Self.rampOffset
            while !bombers[b].done {
                let aim = bombers[b].aims[bombers[b].released]
                guard (ramp-aim)*h >= -bombLead(aim,from:bombers[b].y) else { break }
                let p = Vec(x:ramp,y:bombers[b].y+14)
                fireBombs.append(FireBomb(position:p,previous:p,velocity:Self.firebombRelease(h)))
                bombers[b].released += 1
                if bombers[b].released == 1 { status = "FIREBOMBS AWAY · CLEAR THE TARGET AREA" }
            }
        }
        bombers.removeAll { $0.done && Self.departed($0.x,heading:$0.heading) }
        var falling: [FireBomb] = []
        for var bomb in fireBombs {
            bomb.previous = bomb.position
            let steps = max(1,Int(hypot(bomb.velocity.x,bomb.velocity.y)*dt/3)+1)
            var open = bomb.position, hit = false
            for _ in 0..<steps {
                let sub = dt/Double(steps)
                bomb.velocity.y += Self.gravity*sub
                bomb.position = bomb.position+bomb.velocity*sub
                if bomb.position.y >= Self.bottom { hit = true; break }
                // A stick laid near the map edge is released while the plane is still beyond
                // it; those canisters fly on into the map. Only one leaving the map is lost.
                if bomb.position.x < 0 || bomb.position.x > Self.width {
                    if (bomb.position.x < 0) == (bomb.velocity.x < 0) { hit = true; break }
                    open = bomb.position; continue
                }
                let m = material(at:bomb.position)
                if m == 0 {
                    // Gaps between trim and roof don't count; breaking into a room does.
                    if bomb.pierce < Self.firebombPierce && bomb.position.y >= Self.top
                        && backdrops[index(Int(bomb.position.x/Self.cell),Int((bomb.position.y-Self.top)/Self.cell))] >= 0 { bomb.through = true }
                    open = bomb.position; continue
                }
                // Punch through the first barrier of building; terrain stops it outright. A
                // canister's hole is far smaller than a block, so masonry stays (glass breaks).
                guard !bomb.through && bomb.pierce > 0 && m != 1 && m != 2 && bomb.position.y >= Self.top else { hit = true; break }
                bomb.pierce -= 1
                bomb.velocity = bomb.velocity*0.9
                if m == 4 { burnAway(index(Int(bomb.position.x/Self.cell),Int((bomb.position.y-Self.top)/Self.cell))) }
            }
            if hit { burst(bomb,at:bomb.position,open:open) } else { falling.append(bomb) }
        }
        fireBombs = falling
    }
    /// A canister bursts: a small charge breaks it open, a fireball rolls up, a pool of gel
    /// spreads over the surface it hit, and burning gobbets splash forward and up.
    func burst(_ bomb: FireBomb, at p: Vec, open: Vec) {
        explode(at:p,radius:14)
        blasts.append(Blast(position:open,radius:46))
        quake(at:p,2.2,cap:6,margin:60)
        if !bombed { bombed = true; status = "FIREBOMBS ON TARGET · TARGET AREA BURNING" }
        let cols = Self.columns, col = Int(open.x/Self.cell), row = Int((open.y-Self.top)/Self.cell)
        for dx in -Self.gelPoolReach...Self.gelPoolReach {
            let c = col+dx
            guard c >= 0 && c < cols else { continue }
            // The open cell resting on the first surface near the impact height.
            var r = max(0,row-6)
            while r < min(Self.rows-1,row+10) && !(voxels[index(c,r)] == 0 && voxels[index(c,r+1)] != 0) { r += 1 }
            if r < min(Self.rows-1,row+10) { addGel(index(c,r),Self.gelPool*Float(0.6+0.8*random)) }
        }
        for _ in 0..<Self.gelDropsPerBomb {
            let a = -Double.pi*(0.06+0.88*random), s = 90+random*260
            gelDrops.append(GelDrop(position:open,velocity:Vec(x:cos(a)*s+bomb.velocity.x*0.35,y:sin(a)*s),life:4))
        }
        for _ in 0..<14 {
            particles.append(Particle(position:open,velocity:Vec(x:(random-0.3)*120,y:-random*90-20),life:2.5+random*2,total:4.5,kind:14,size:10+random*14))
        }
        for _ in 0..<24 {
            particles.append(Particle(position:open,velocity:Vec(x:(random-0.4)*260,y:-random*220),life:0.6+random*0.8,total:1.4,kind:8,size:1.5+random*2))
        }
    }
    func updateGel(_ dt: Double) {
        var flying: [GelDrop] = []
        for var d in gelDrops {
            d.life -= dt
            let steps = max(1,Int(hypot(d.velocity.x,d.velocity.y)*dt/3)+1)
            var landed = false
            for _ in 0..<steps {
                let sub = dt/Double(steps), before = d.position
                d.velocity.y += Self.gravity*sub
                d.position = d.position+d.velocity*sub
                if d.position.x < 0 || d.position.x >= Self.width || d.position.y >= Self.bottom { landed = true; break }
                if material(at:d.position) != 0 {
                    // Stick in the open cell just in front of whatever it hit.
                    if before.y >= Self.top {
                        addGel(index(Int(before.x/Self.cell),Int((before.y-Self.top)/Self.cell)),Self.gelPerDrop*Float(0.6+0.8*random))
                    }
                    landed = true; break
                }
            }
            if !landed && d.life > 0 { flying.append(d) }
        }
        gelDrops = flying
    }
    func updateEmbers(_ dt: Double) {
        var aloft: [Ember] = []
        for var e in embers {
            e.life -= dt
            e.velocity.y += 90*dt
            e.velocity.x *= exp(-0.8*dt)
            e.position = e.position+e.velocity*dt
            guard e.life > 0, e.position.x >= 0, e.position.x < Self.width, e.position.y < Self.bottom else { continue }
            if e.position.y >= Self.top {
                let i = index(Int(e.position.x/Self.cell),Int((e.position.y-Self.top)/Self.cell))
                if selfBurnable(i) && fire.flame[i] <= 0 { heatCell(i,1.4); continue }
                if voxels[i] != 0 { continue }
            }
            aloft.append(e)
        }
        embers = aloft
    }
    /// One step of the fire automaton; see `FireField`.
    func stepFire(_ dt: Float) {
        let cols = Self.columns, rows = Self.rows
        let current = fire.burning
        fire.burning = []; fire.burning.reserveCapacity(current.count)
        var smoke = 20
        for i in current {
            var f = fire.flame[i]
            guard f > 0 else { fire.listed[i] = false; continue }
            let x = i%cols, y = i/cols, m = voxels[i]
            // Water floods the fire out in a burst of steam. Napalm floats and burns on.
            if water.mass[i] > 0.25 && fire.gel[i] <= 0 {
                fire.flame[i] = 0; fire.listed[i] = false
                if smoke > 0 {
                    smoke -= 1
                    particles.append(Particle(position:Vec(x:(Double(x)+0.5)*Self.cell,y:Double(y)*Self.cell+Self.top),velocity:Vec(x:(water.random()-0.5)*20,y:-30-water.random()*30),life:1.5+water.random(),total:2.5,kind:Self.mistKind,size:6+water.random()*6))
                }
                continue
            }
            let own = selfBurnable(i)
            if !own && fire.gel[i] <= 0 { fire.flame[i] = 0; fire.listed[i] = false; continue }
            // Gel with nothing under it runs down; gel on a wall face slowly slides.
            if m == 0 && !own && fire.gel[i] > 0 && y+1 < rows && voxels[i+cols] == 0 {
                let side = (x > 0 && voxels[i-1] != 0) || (x+1 < cols && voxels[i+1] != 0)
                if !side || random < 0.08 {
                    let j = i+cols
                    fire.gel[j] = min(Self.gelLimit,fire.gel[j]+fire.gel[i]); fire.gel[i] = 0
                    fire.flame[i] = 0; fire.listed[i] = false
                    ignite(j,f)
                    continue
                }
            } else if m == 0 && !own && fire.gel[i] > 0 && y+1 >= rows {
                fire.gel[i] = 0; fire.flame[i] = 0; fire.listed[i] = false; continue
            }
            // Open faces feed a burning solid; air cells always have air.
            var open = 0
            if x > 0 && voxels[i-1] == 0 { open += 1 }
            if x+1 < cols && voxels[i+1] == 0 { open += 1 }
            if y > 0 && voxels[i-cols] == 0 { open += 1 }
            if y+1 < rows && voxels[i+cols] == 0 { open += 1 }
            let air: Float = m == 0 ? 1 : 0.3+0.35*Float(min(open,2))
            let supply = fire.gel[i]+(own ? ownFuel(i) : 0)
            let target = air*min(1,supply/3)
            // Flames build quickly, ease back as fuel thins, and gutter out fast once it is gone.
            f += (target-f)*(target > f ? 1.5 : supply <= 0 ? 3 : 0.8)*dt
            var burn = f*dt
            let used = min(fire.gel[i],burn); fire.gel[i] -= used; burn -= used
            if own && burn > 0 { fire.fuel[i] = max(0,fire.fuel[i]-burn) }
            if f < 0.03 && supply-f*dt <= 0.05 {
                burnOut(i); continue
            }
            fire.flame[i] = f
            fire.burning.append(i)
            for s in Self.heatSpread {
                let nx = x+s.dx, ny = y+s.dy
                guard nx >= 0 && nx < cols && ny >= 0 && ny < rows else { continue }
                if s.dy == -2 && voxels[i-cols] != 0 { continue }
                heatCell(ny*cols+nx,f*s.w*dt)
            }
            if fire.gel[i] > 0 {
                for n in [i-1,i+1,i-cols,i+cols] where n >= 0 && n < voxels.count && voxels[n] != 0 && abs(n%cols-x) <= 1 { heatCell(n,f*Self.gelContact*dt) }
            }
            // Smoke and embers leave where the fire meets open air outside.
            let vent = y > 0 && voxels[i-cols] == 0 && backdrops[i-cols] < 0 && fire.flame[i-cols] <= 0
                || (m == 0 && ((x > 0 && voxels[i-1] == 0 && backdrops[i-1] < 0) || (x+1 < cols && voxels[i+1] == 0 && backdrops[i+1] < 0)))
            guard vent else { continue }
            let top = Vec(x:(Double(x)+0.5)*Self.cell,y:Double(y)*Self.cell+Self.top)
            if smoke > 0 && random < 0.05*Double(f) {
                smoke -= 1
                particles.append(Particle(position:top,velocity:Vec(x:(random-0.5)*14,y:-22-random*26),life:3+random*3,total:6,kind:14,size:6+random*8))
            }
            if f > 0.6 && embers.count < Self.maxEmbers && random < 0.006*Double(f) {
                embers.append(Ember(position:top,velocity:Vec(x:(random-0.5)*70,y:-70-random*100),life:2+random*2.5))
            }
        }
        // Heat held by fuel that has not caught leaks away.
        let keep = exp(-Self.heatLoss*dt)
        var warm: [Int] = []
        warm.reserveCapacity(fire.warm.count)
        for n in fire.warm {
            if fire.flame[n] > 0 { fire.heat[n] = 0; continue }
            fire.heat[n] *= keep
            if fire.heat[n] < 0.02 { fire.heat[n] = 0 } else { warm.append(n) }
        }
        fire.warm = warm
        if fireShattered { fireShattered = false; onSound?(SoundEvent(cue:.glass,x:nil,gain:0.6)) }
    }
    /// A cell that has run out of fuel goes out, leaving soot, or ash where a crate or
    /// sandbag stood.
    func burnOut(_ i: Int) {
        fire.flame[i] = 0; fire.listed[i] = false; fire.gel[i] = 0
        let m = voxels[i], cols = Self.columns
        if m == 6 || m == 7 { fire.fuel[i] = 0; burnAway(i) }
        else if m == 0 && backdrops[i] >= 0 { fire.char[i] = 3 }
        for n in [i-1,i+1,i-cols,i+cols] where n >= 0 && n < voxels.count && voxels[n] != 0 && abs(n%cols-i%cols) <= 1 {
            fire.char[n] = max(fire.char[n],2)
        }
    }
    /// Clears every fire, firebomber, canister, gobbet, and ember.
    func resetFire() {
        fire = FireField(); bombers = []; fireBombs = []; gelDrops = []; embers = []
        firebombCooldown = 0; bombed = false; fireShattered = false
    }
}
