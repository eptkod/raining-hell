import Foundation

/// A gout of water thrown clear of the surface by a blast or a section crashing into it. It
/// flies under gravity carrying `mass` (in cells of water) and pours it back into the grid
/// wherever it comes down, so a blast really does move water from one place to another.
struct WaterDrop { var position: Vec; var velocity: Vec; var mass: Float; var life: Double }

/// Water for every cell of the voxel grid.
///
/// Unlike fire, which is heat spreading through fuel, water is a conserved quantity that
/// flows. The model is a mass-transfer cellular automaton run at `World.waterStep`:
/// * Each open cell holds `mass`, 1 being a full cell. Water falls into the cell below until
///   that is full, then levels out with its neighbours to either side.
/// * Sideways flow is driven by pressure: the level the water in a cell's column stands at
///   (`World.surfaceLevel`), shared across every row two columns have in common. It has
///   momentum (`flux`), so a breach low in a dam or a hull drains everything above it in a
///   surge, floods slosh, and water finds its own level on both sides of a U-bend. Water is
///   nearly incompressible, so what crosses between two full columns comes off the top of one
///   and lifts the other.
/// * Only cells that are moving, or next to cells that moved, are stepped. Settled water is
///   dormant; its `rim` (the cells touching anything that is not water) is checked every
///   `World.rimCheck` seconds, so a blast, a fire or a collapse that opens a hole next to a
///   still pool wakes it and the water floods in.
/// * Soil, rubble, sandbags and timber drink water that touches them until they are saturated,
///   using up some of it, and the dampness wicks slowly on through the ground. Everything else
///   just gets wet on the surface and dries off again. `soak` is that dampness; it darkens the
///   cell when drawn and keeps fuel from catching fire.
/// * Blasts throw water out as `WaterDrop`s, and falling sections shove it aside, so it
///   splashes, sloshes back and floods craters rather than sitting still.
struct WaterField {
    static var count: Int { World.columns*World.rows }
    /// Water in each open cell; 1 is full, slightly more when compressed under depth.
    var mass = [Float](repeating:0,count:count)
    /// Scratch copy flows are summed into during a pass; equal to `mass` between passes.
    var next = [Float](repeating:0,count:count)
    /// Sideways flow from each cell to the one east of it (negative runs west). It carries
    /// over between passes, so water has momentum: a breach accelerates the whole body
    /// toward it and floods surge and slosh, instead of seeping out a cell at a time.
    var flux = [Float](repeating:0,count:count)
    /// Surface level and column floor of each cell, worked out once per pass (see
    /// `World.surfaceLevel`), the pass they were worked out in, and scratch for the walk.
    var levelOf = [Float](repeating:0,count:count), levelStamp = [UInt32](repeating:0,count:count)
    /// The surface cell at the top of each cell's column, found with its level.
    var topOf = [Int](repeating:0,count:count)
    var floorOf = [Float](repeating:0,count:count)
    /// Pass a cell was listed for, so each pair of neighbours is stepped once per pass.
    var inPass = [UInt32](repeating:0,count:count)
    /// Smoothed horizontal and downward flow through each cell, for drawing foam and streaks.
    var vx = [Float](repeating:0,count:count)
    var vy = [Float](repeating:0,count:count)
    /// Dampness of a solid cell, 0 (dry) to 1 (saturated).
    var soak = [Float](repeating:0,count:count)
    /// `soak` in five steps, for drawing (so the terrain tile cache only redraws on a visible change).
    var wet = [UInt8](repeating:0,count:count)
    /// Cells to step on the next pass, and whether a cell is already listed.
    var active: [Int] = []
    var listed = [Bool](repeating:false,count:count)
    /// Pass each cell was last touched in, so a pass commits each cell once.
    var stamp = [UInt32](repeating:0,count:count)
    var pass: UInt32 = 0
    /// Settled water touching something that is not water; see the type comment.
    var rim: [Int] = []
    var onRim = [Bool](repeating:false,count:count)
    /// Damp solids still wicking water on or drying off.
    var damp: [Int] = []
    var dampListed = [Bool](repeating:false,count:count)
    var drops: [WaterDrop] = []
    var clock = 0.0, rimClock = 0.0, dampClock = 0.0
    /// The water's own random stream, so splashes never shift the world's (tests replay it).
    var seed: UInt64 = 7
    mutating func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) & 0x7fffffff) / Double(0x7fffffff)
    }
}

extension World {
    /// Seconds between passes of the water automaton: 180 a second, fast enough that a
    /// breached reservoir pours rather than seeps.
    static let waterStep = 1.0/180
    /// Most passes one frame runs, so a long frame can't stall the game catching up.
    static let maxWaterPasses = 8
    /// Extra mass a full cell under water settles at. Pressure itself comes from the level of
    /// the column above (`surfaceLevel`); this hair of compression only lets water be pushed
    /// up into a column that is already full, as through a U-bend.
    static let waterCompress: Float = 0.002
    /// Most water that moves between two cells in a pass.
    static let waterSpeed: Float = 1
    /// Share of last pass's sideways flow a pair keeps, and how much a difference in level adds
    /// to it each pass. Together they give water its momentum; see `WaterField.flux`.
    static let waterCarry: Float = 0.97
    static let waterPush: Float = 0.5
    /// Neighbours this close in level don't flow, so a wide pool settles instead of creeping.
    static let waterLevelTolerance: Float = 0.003
    /// A film thinner than this stays put on a floor rather than spreading out.
    static let waterFilm: Float = 0.04
    /// Water below this in a cell evaporates.
    static let waterTrace: Float = 0.002
    static let rimCheck = 0.15
    static let dampCheck = 0.25
    /// Water absorbent cells drink per pass from each face that touches water.
    static let soakRate: Float = 0.004
    static let maxWaterDrops = 900
    /// Spray, foam and mist particles share `particles`; these are their kinds.
    static let sprayKind = 15, mistKind = 16

    /// Water a dry cell of this material can soak up, in cells of water; 0 for materials that
    /// only get wet on the surface.
    static func absorbency(_ m: UInt8) -> Float {
        switch m {
        case 1: return 0.6     // soil
        case 10: return 0.45   // rubble
        case 6: return 0.8     // sandbags
        case 7: return 0.4     // timber crates
        default: return 0
        }
    }
    /// What the lower of two stacked cells holds when they share `total`: full, and a hair
    /// over once there is more than a cellful. Anything beyond that rises; water squeezed into
    /// a column shows in its level (`surfaceLevel`), which drives it out sideways.
    static func stableBelow(_ total: Float) -> Float { total <= 1 ? 1 : min(total,1+waterCompress) }
    /// Water a cell of this material holds when full: 1 for open space, a share of it for
    /// rubble, which is loose enough for water to seep through, and none for anything solid.
    @inline(__always) static func waterRoom(_ m: UInt8) -> Float { m == 0 ? 1 : m == 10 ? rubblePorosity : 0 }
    static let rubblePorosity: Float = 0.4
    /// Share of a flow that gets through rubble in a pass, compared with open water.
    static let seepRate: Float = 0.25

    // MARK: Setting up
    /// Fills the level's pools and wets the ground around them, as if they had always been there.
    func seedWater() {
        water = WaterField()
        let cols = Self.columns, rows = Self.rows
        // Each pool floods every open cell it reaches without rising above its surface, so
        // pockets under ledges and arches below the waterline fill too.
        for pool in pools {
            let x0 = max(0,pool.x0), x1 = min(cols-1,pool.x1), top = max(0,pool.row)
            var queue: [Int] = []
            for x in x0...x1 where top < rows && voxels[index(x,top)] == 0 && water.mass[index(x,top)] == 0 {
                water.mass[index(x,top)] = 1; queue.append(index(x,top))
            }
            var head = 0
            while head < queue.count {
                let i = queue[head]; head += 1
                let x = i%cols, y = i/cols
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y+1),(x,y-1)] where nx >= x0 && nx <= x1 && ny >= top && ny < rows {
                    let n = index(nx,ny)
                    if voxels[n] == 0 && water.mass[n] == 0 { water.mass[n] = 1; queue.append(n) }
                }
            }
        }
        // Start below the surface at the hair of compression water settles at, so still water
        // is still and stays at its level when something wakes it.
        for i in water.mass.indices where water.mass[i] > 0 && i >= cols && water.mass[i-cols] > 0 {
            water.mass[i] = 1+Self.waterCompress
        }
        water.next = water.mass
        // Banks and beds have been under water for years: saturated where they touch it,
        // fading over the next couple of cells, already at the balance wicking would reach.
        for i in water.mass.indices where water.mass[i] > 0 {
            let x = i%cols, y = i/cols
            for dy in -1...3 {
                for dx in -3...3 where abs(dx)+max(0,dy) <= 3 && (dy >= 0 || dx != 0) {
                    let nx = x+dx, ny = y+dy
                    guard nx >= 0 && nx < cols && ny >= 0 && ny < rows else { continue }
                    let n = index(nx,ny), m = voxels[n]
                    guard m != 0 else { continue }
                    let d = abs(dx)+max(0,dy)
                    let s: Float = Self.absorbency(m) > 0 ? 1-0.25*Float(d-1) : (d == 1 ? 0.6 : 0)
                    if s > water.soak[n] { water.soak[n] = s; water.wet[n] = Self.wetLevel(s) }
                }
            }
            if touchesDry(i) { water.onRim[i] = true; water.rim.append(i) }
        }
    }
    static func wetLevel(_ s: Float) -> UInt8 { UInt8(max(0,min(4,Int((s*4).rounded())))) }
    /// Whether a water cell borders anything but water: a solid, or air it might spill into.
    func touchesDry(_ i: Int) -> Bool {
        let cols = Self.columns, x = i%cols
        for n in [x > 0 ? i-1 : -1, x+1 < cols ? i+1 : -1, i+cols, i-cols] where n >= 0 && n < voxels.count {
            if voxels[n] != 0 || water.mass[n] < 0.99 { return true }
        }
        return false
    }

    // MARK: Changing the water from outside the automaton
    /// Lists a cell to be stepped on the next pass.
    func wakeWater(_ i: Int) {
        guard i >= 0 && i < voxels.count, !water.listed[i] else { return }
        water.listed[i] = true; water.active.append(i)
    }
    /// Sets a cell's water, keeping the scratch copy in step, and wakes it and its neighbours.
    func setWater(_ i: Int, _ amount: Float) {
        water.mass[i] = amount; water.next[i] = amount
        let cols = Self.columns, x = i%cols
        wakeWater(i)
        if x > 0 { wakeWater(i-1) }
        if x+1 < cols { wakeWater(i+1) }
        wakeWater(i-cols); wakeWater(i+cols)
    }
    /// Pours water into the open cell `i`, or the nearest open cell above it.
    func pourWater(_ i: Int, _ amount: Float) {
        guard amount > 0 else { return }
        var k = i
        while k >= 0 && Self.waterRoom(voxels[k]) < 1 { k -= Self.columns }
        guard k >= 0 else { return }
        setWater(k,water.mass[k]+amount)
    }
    /// A block has just landed in a cell holding water: the water is pushed up out of its way.
    func displaceWater(_ i: Int) {
        guard i >= 0 && i < voxels.count else { return }
        let m = water.mass[i], room = Self.waterRoom(voxels[i])
        guard m > room else { if m > 0 { wakeWater(i) }; return }
        setWater(i,room)
        pourWater(i,m-room)
    }

    // MARK: Simulation
    /// Advances the water, the spray in the air, and the damp in the ground by one frame.
    func updateWater(_ dt: Double) {
        updateWaterDrops(dt)
        water.clock += dt
        var passes = 0
        while water.clock >= Self.waterStep && passes < Self.maxWaterPasses {
            water.clock -= Self.waterStep; passes += 1
            if !water.active.isEmpty { waterPass() }
        }
        if passes == Self.maxWaterPasses { water.clock = 0 }
        water.rimClock += dt
        if water.rimClock >= Self.rimCheck { water.rimClock = 0; checkRim() }
        water.dampClock += dt
        if water.dampClock >= Self.dampCheck { water.dampClock = 0; stepDamp() }
    }
    /// One pass of the automaton over the cells that are moving; see `WaterField`.
    func waterPass() {
        let cols = Self.columns, rows = Self.rows
        water.pass &+= 1
        let pass = water.pass
        let current = water.active
        water.active = []; water.active.reserveCapacity(current.count)
        for i in current { water.listed[i] = false; water.inPass[i] = pass }
        var touched: [Int] = []
        touched.reserveCapacity(current.count*2)
        var transfers: [(Int,Int,Int,Float)] = []
        @inline(__always) func touch(_ j: Int) {
            if water.stamp[j] != pass { water.stamp[j] = pass; touched.append(j) }
        }
        // Gives water to a column at cell `k`: it fills that cell, then stacks up into the open
        // cells above it, as water lifted from below would, rather than packing into one cell.
        @inline(__always) func deposit(_ k: Int, _ amount: Float) {
            var k = k, left = amount
            while left > 0 {
                touch(k)
                let up = k-cols
                let room = max(0,1-water.next[k])
                if room >= left || up < 0 || voxels[up] != 0 { water.next[k] += left; return }
                water.next[k] += room; left -= room
                k = up
            }
        }
        // Moves `f` from cell i to cell j, and records it as flow for drawing.
        @inline(__always) func move(_ i: Int, _ j: Int, _ f: Float, _ dx: Float, _ dy: Float) {
            water.next[i] -= f; water.next[j] += f
            touch(j)
            let g: Float = 0.02*f
            water.vx[i] += g*dx; water.vy[i] += g*dy; water.vx[j] += g*dx; water.vy[j] += g*dy
        }
        for i in current {
            touch(i)
            let m = water.mass[i]
            guard m > 0 else { continue }
            let room = Self.waterRoom(voxels[i])
            if room < 1 && m > room {
                // Something landed in this cell: what no longer fits goes up out of its way.
                let excess = m-room
                water.next[i] -= excess
                var k = i-cols
                while k >= 0 && Self.waterRoom(voxels[k]) < 1 { k -= cols }
                if k >= 0 { water.next[k] += excess; touch(k) }
                if room == 0 { continue }
            }
            let x = i%cols, y = i/cols
            var remaining = m
            if room < 1 {
                // Water seeping through a rubble pile: it runs down and out sideways, slowly.
                remaining = min(m,room)
                water.soak[i] = 1; water.wet[i] = 4
                let level = remaining/room
                if y+1 < rows {
                    let b = i+cols, rb = Self.waterRoom(voxels[b])
                    if rb > 0 {
                        let f = max(0,min(remaining,rb-water.mass[b]))*Self.seepRate
                        if f > 0 { move(i,b,f,0,1); remaining -= f }
                    }
                }
                for (n,dx) in [(x > 0 ? i-1 : -1,Float(-1)),(x+1 < cols ? i+1 : -1,Float(1))] where n >= 0 && remaining > 0 {
                    let rn = Self.waterRoom(voxels[n])
                    guard rn > 0 else { continue }
                    let d = level-water.mass[n]/rn
                    guard d > Self.waterLevelTolerance else { continue }
                    let f = min(d/3*min(room,rn)*Self.seepRate,remaining)
                    move(i,n,f,dx,0); remaining -= f
                }
                if x > 0, !water.listed[i-1], Self.waterRoom(voxels[i-1]) > 0, water.mass[i-1]/Self.waterRoom(voxels[i-1]) > level+Self.waterLevelTolerance { wakeWater(i-1) }
                if x+1 < cols, !water.listed[i+1], Self.waterRoom(voxels[i+1]) > 0, water.mass[i+1]/Self.waterRoom(voxels[i+1]) > level+Self.waterLevelTolerance { wakeWater(i+1) }
                if y > 0, level < 0.99, !water.listed[i-cols], water.mass[i-cols] > 0 { wakeWater(i-cols) }
                continue
            }
            // Thirsty ground drinks from each face this water touches.
            for n in [y+1 < rows ? i+cols : -1, x > 0 ? i-1 : -1, x+1 < cols ? i+1 : -1, y > 0 ? i-cols : -1] where n >= 0 && voxels[n] != 0 {
                let cap = Self.absorbency(voxels[n])
                if cap > 0 {
                    guard water.soak[n] < 1, remaining > 0 else { continue }
                    let take = min(remaining*0.5,Self.soakRate,(1-water.soak[n])*cap)
                    water.soak[n] += take/cap; water.next[i] -= take; remaining -= take
                    water.wet[n] = Self.wetLevel(water.soak[n])
                    addDamp(n)
                } else if water.soak[n] < 0.6 {
                    water.soak[n] = 0.6; water.wet[n] = Self.wetLevel(0.6); addDamp(n)
                }
            }
            // Down: fill the cell below, compressing it under depth, or soak into rubble.
            if y+1 < rows {
                let b = i+cols, rb = Self.waterRoom(voxels[b]), below = water.mass[b]
                if rb == 1 {
                    // Halving every vertical flow keeps a column from rocking between two states.
                    var f = (Self.stableBelow(remaining+below)-below)*0.5
                    f = max(0,min(f,min(Self.waterSpeed,remaining)))
                    if f > 0 { move(i,b,f,0,1); remaining -= f }
                } else if rb > 0 {
                    let f = max(0,min(remaining,rb-below))*Self.seepRate
                    if f > 0 { move(i,b,f,0,1); remaining -= f }
                }
            }
            guard remaining > 0 else { continue }
            // Sideways. Between two open cells the flow has momentum: it keeps what it had and
            // gathers more from the difference in level (or pressure, deeper down). Each pair is
            // stepped once, by its west cell unless that one is dormant. Rubble seeps slowly.
            let film = m < Self.waterFilm && (y+1 >= rows || voxels[i+cols] != 0 || water.mass[i+cols] >= 0.99)
            for (n,dx) in [(x > 0 ? i-1 : -1,Float(-1)),(x+1 < cols ? i+1 : -1,Float(1))] where n >= 0 {
                let rn = Self.waterRoom(voxels[n])
                guard rn > 0 else { continue }
                if rn == 1 {
                    if dx < 0 && water.inPass[n] == pass { continue }
                    let a = dx > 0 ? i : n, b = a+1
                    let ma = water.mass[a], mb = water.mass[b]
                    // The push is the difference between the two columns' surfaces (the head),
                    // shared across every row the columns have in common so a deep body and a
                    // shallow sheet level out alike.
                    let la = surfaceLevel(a,pass), lb = surfaceLevel(b,pass), d = lb-la
                    let span = max(1,max(columnFloor(a,pass),columnFloor(b,pass))-min(la,lb))
                    var f = water.flux[a]*Self.waterCarry+Self.waterPush*d/span
                    if abs(d) < Self.waterLevelTolerance && abs(f) < 0.003 { f = 0 }
                    // Water is all but incompressible: what crosses between two full columns
                    // below their surfaces comes off the top of one and lifts the other, so it
                    // is taken from and given to the surface cells. A film doesn't spread, and
                    // no cell gives more than it has.
                    let from = f > 0 ? a : b, to = f > 0 ? b : a
                    let donor = water.mass[from] >= 0.99 ? water.topOf[from] : from
                    var taker = water.mass[to] >= 0.99 ? water.topOf[to] : to
                    // A full surface cell passes what it is given up into the open air above it.
                    if water.mass[taker] >= 0.99 && taker >= cols && voxels[taker-cols] == 0 { taker -= cols }
                    if donor == i {
                        var amount = film && water.mass[i] < Self.waterFilm ? 0 : min(abs(f),remaining)
                        if amount < 0 { amount = 0 }
                        water.flux[a] = f > 0 ? amount : -amount
                        if amount > 0 {
                            water.next[i] -= amount; deposit(taker,amount); remaining -= amount
                            let g: Float = 0.02*amount*(f > 0 ? 1 : -1)
                            water.vx[a] += g; water.vx[b] += g
                        }
                    } else {
                        // Settled once every cell has spent its own water this pass.
                        water.flux[a] = f
                        transfers.append((a,donor,taker,f))
                    }
                    _ = ma; _ = mb
                } else if !film {
                    let d = min(m,1)-water.mass[n]/rn
                    guard d > Self.waterLevelTolerance else { continue }
                    let f = min(d/3*rn*Self.seepRate,remaining)
                    if f > 0 { move(i,n,f,dx,0); remaining -= f }
                }
                guard remaining > 0 else { break }
            }
            guard remaining > 0 else { continue }
            // Up: water compressed beyond what the cell above settles at rises into it.
            if y > 0 && voxels[i-cols] == 0 {
                var f = (remaining-Self.stableBelow(remaining+water.mass[i-cols]))*0.5
                f = max(0,min(f,min(Self.waterSpeed,remaining)))
                if f > 0 { water.next[i] -= f; water.next[i-cols] += f; touch(i-cols) }
            }
            // A dormant neighbour that should be flowing into this cell is woken for the next pass.
            for n in [x > 0 ? i-1 : -1, x+1 < cols ? i+1 : -1] where n >= 0 && !water.listed[n] {
                let rn = Self.waterRoom(voxels[n])
                if rn > 0 && water.mass[n]/rn > min(m,rn == 1 ? m : 1)+Self.waterLevelTolerance { wakeWater(n) }
            }
            if y > 0, m < 0.99, !water.listed[i-cols], water.mass[i-cols] > 0 { wakeWater(i-cols) }
        }
        // Exchanges between columns come off what each surface cell has left.
        // Each comes off the top of the giving column, working down it if the surface cell
        // is nearly empty.
        for (a,donor,taker,f) in transfers {
            var need = min(abs(f),Self.waterSpeed*0.5), amount: Float = 0, k = donor
            while need > 0.0001 && k < voxels.count && voxels[k] == 0 {
                let take = min(need,max(0,water.next[k])*0.9)
                if take > 0 { water.next[k] -= take; touch(k); amount += take; need -= take }
                guard water.mass[k] > 0.5 || k == donor else { break }
                k += cols
            }
            water.flux[a] = f > 0 ? amount : -amount
            guard amount > 0 else { continue }
            deposit(taker,amount)
            let g: Float = 0.02*amount*(f > 0 ? 1 : -1)
            water.vx[a] += g; water.vx[a+1] += g
        }
        let keep: Float = 0.98
        for t in touched {
            let old = water.mass[t]
            var new = max(0,water.next[t])
            // A stray trace with no water beside it dries up; one at the edge of a body stays
            // part of it, so moving water doesn't wear away.
            if new < Self.waterTrace && new > 0 {
                let x = t%cols
                let near = (x > 0 && water.next[t-1] > Self.waterTrace) || (x+1 < cols && water.next[t+1] > Self.waterTrace)
                    || (t >= cols && water.next[t-cols] > Self.waterTrace) || (t+cols < voxels.count && water.next[t+cols] > Self.waterTrace)
                if !near { new = 0 }
            }
            water.mass[t] = new; water.next[t] = new
            water.vx[t] *= keep; water.vy[t] *= keep
            // A steady stream keeps flowing even when no cell in it changes.
            let stirring = abs(water.vx[t])+abs(water.vy[t]) > 0.01 || abs(water.flux[t]) > 0.003
            if abs(new-old) > 0.0004 || (stirring && new > 0) {
                wakeWater(t)
                let x = t%cols
                if x > 0 && Self.waterRoom(voxels[t-1]) > 0 { wakeWater(t-1) }
                if x+1 < cols && Self.waterRoom(voxels[t+1]) > 0 { wakeWater(t+1) }
                if t >= cols && Self.waterRoom(voxels[t-cols]) > 0 { wakeWater(t-cols) }
                if t+cols < voxels.count && Self.waterRoom(voxels[t+cols]) > 0 { wakeWater(t+cols) }
            } else {
                water.vx[t] = 0; water.vy[t] = 0; water.flux[t] = 0
                if new > 0 && !water.onRim[t] && touchesDry(t) { water.onRim[t] = true; water.rim.append(t) }
            }
        }
        sprayFromRapids(touched)
    }
    /// Height (as a row, fractions counting down from the top of the cell) the water over cell
    /// `i` would stand at: the floor of the unbroken column of water it is part of, less all
    /// the water in that column. Water is all but incompressible, so any squeezed into the
    /// column stands it higher. An empty cell's level is its own floor. Worked out once per
    /// pass for a whole column at a time, with the column's surface cell (`topOf`) and floor.
    func surfaceLevel(_ i: Int, _ pass: UInt32) -> Float {
        if water.levelStamp[i] == pass { return water.levelOf[i] }
        let cols = Self.columns
        guard water.mass[i] > Self.waterTrace else {
            let row = Float(i/cols+1)
            water.levelStamp[i] = pass; water.levelOf[i] = row; water.floorOf[i] = row; water.topOf[i] = i
            return row
        }
        @inline(__always) func joined(_ k: Int) -> Bool { k >= 0 && k < voxels.count && voxels[k] == 0 && water.mass[k] >= 0.5 }
        var top = i
        while joined(top) && top >= cols && voxels[top-cols] == 0 && water.mass[top-cols] > Self.waterTrace { top -= cols }
        var bottom = i
        while joined(bottom) && joined(bottom+cols) { bottom += cols }
        var sum: Float = 0, k = top
        while k <= bottom { sum += water.mass[k]; k += cols }
        let floor = Float(bottom/cols+1), level = floor-sum
        k = top
        while k <= bottom {
            water.levelStamp[k] = pass; water.levelOf[k] = level; water.floorOf[k] = floor; water.topOf[k] = top
            k += cols
        }
        return level
    }
    /// Row just below the bottom of the column of water cell `i` is part of.
    func columnFloor(_ i: Int, _ pass: UInt32) -> Float {
        _ = surfaceLevel(i,pass)
        return water.floorOf[i]
    }
    /// Whitewater: fast water breaking at the surface throws up spray and mist.
    func sprayFromRapids(_ cells: [Int]) {
        guard particles.count < 2400 else { return }
        let cols = Self.columns
        var budget = 3
        for t in cells where budget > 0 {
            let speed = abs(water.vx[t])+abs(water.vy[t])
            guard speed > 0.12, water.mass[t] > 0.2, t >= cols, voxels[t-cols] == 0, water.mass[t-cols] < 0.05 else { continue }
            guard water.random() < Double(speed)*0.02 else { continue }
            budget -= 1
            let p = Vec(x:(Double(t%cols)+water.random())*Self.cell,y:Double(t/cols)*Self.cell+Self.top)
            let push = Double(water.vx[t])*900
            particles.append(Particle(position:p,velocity:Vec(x:push+(water.random()-0.5)*40,y:-40-water.random()*90*Double(min(1,speed*3))),life:0.5+water.random()*0.5,total:1,kind:Self.sprayKind,size:1+water.random()*1.5))
            if water.random() < 0.3 {
                particles.append(Particle(position:p,velocity:Vec(x:push*0.3,y:-12-water.random()*14),life:1+water.random(),total:2,kind:Self.mistKind,size:5+water.random()*6))
            }
        }
    }
    /// Wakes settled water whose surroundings have changed: a wall blown out beside it, a
    /// floor burnt through under it, rubble dropped into it.
    func checkRim() {
        let cols = Self.columns
        var kept: [Int] = []
        kept.reserveCapacity(water.rim.count)
        for i in water.rim {
            let m = water.mass[i]
            guard m > 0, !water.listed[i] else { water.onRim[i] = false; continue }
            let room = Self.waterRoom(voxels[i])
            if room < 1 && m > room+0.01 { water.onRim[i] = false; wakeWater(i); continue }
            let x = i%cols, level = min(1,m/max(room,0.01))
            func lower(_ n: Int, _ by: Float) -> Bool {
                let rn = Self.waterRoom(voxels[n])
                return rn > 0 && water.mass[n]/rn < level-by
            }
            var spill = i+cols < voxels.count && lower(i+cols,0.01)
            if !spill && m >= Self.waterFilm {
                spill = (x > 0 && lower(i-1,0.02)) || (x+1 < cols && lower(i+1,0.02))
            }
            // Ground beside it that is still drinking keeps it soaking in.
            if !spill {
                for n in [i+cols, x > 0 ? i-1 : -1, x+1 < cols ? i+1 : -1] where n >= 0 && n < voxels.count {
                    if Self.absorbency(voxels[n]) > 0 && water.soak[n] < 0.98 { spill = true; break }
                }
            }
            if spill { water.onRim[i] = false; wakeWater(i) } else { kept.append(i) }
        }
        water.rim = kept
    }
    func addDamp(_ i: Int) {
        guard !water.dampListed[i] else { return }
        water.dampListed[i] = true; water.damp.append(i)
    }
    /// Damp soaks on through the ground, and wet stone, steel and glass dry off.
    func stepDamp() {
        let cols = Self.columns
        let current = water.damp
        water.damp = []
        for i in current { water.dampListed[i] = false }
        for i in current {
            let m = voxels[i]
            guard m != 0 else { water.soak[i] = 0; water.wet[i] = 0; continue }
            let cap = Self.absorbency(m), x = i%cols
            let sides = [(i+cols,Float(1)),(x > 0 ? i-1 : -1,Float(0.5)),(x+1 < cols ? i+1 : -1,Float(0.5)),(i-cols,Float(0.2))]
            var busy = false
            if cap > 0 {
                for (n,w) in sides where n >= 0 && n < voxels.count {
                    let other = Self.absorbency(voxels[n])
                    guard other > 0, water.soak[i]-water.soak[n] > 0.25 else { continue }
                    let amount = (water.soak[i]-water.soak[n])*0.15*w*min(cap,other)
                    water.soak[i] -= amount/cap; water.soak[n] += amount/other
                    water.wet[n] = Self.wetLevel(water.soak[n]); addDamp(n)
                    busy = true
                }
            } else {
                let touching = sides.contains { $0.0 >= 0 && $0.0 < voxels.count && voxels[$0.0] == 0 && water.mass[$0.0] > 0.05 }
                if !touching { water.soak[i] = max(0,water.soak[i]-0.012) }
                busy = !touching && water.soak[i] > 0
            }
            water.wet[i] = Self.wetLevel(water.soak[i])
            if busy { addDamp(i) }
        }
    }

    // MARK: Splashes
    /// A blast at `p` throws the water around it into the air. Under the surface it sends up
    /// a tall white column; at the edge of a pool it throws a sheet of water outward.
    func splashWater(at p: Vec, radius: Double) {
        let c = Self.cell, cols = Self.columns
        let reach = radius*1.4
        let cx = Int(p.x/c), cy = Int((p.y-Self.top)/c), r = Int(reach/c)+1
        guard cx+r >= 0 && cx-r < cols && cy+r >= 0 && cy-r < Self.rows else { return }
        // How deep the blast went off: water above the burst makes the plume a column.
        var depth = 0
        while cy-depth-1 >= 0 && cx >= 0 && cx < cols && water.mass[index(cx,cy-depth-1)] > 0.3 && depth < 40 { depth += 1 }
        var cells: [(Int,Float,Double)] = []
        var total: Float = 0
        for y in max(0,cy-r)...min(Self.rows-1,cy+r) {
            for x in max(0,cx-r)...min(cols-1,cx+r) {
                let i = index(x,y)
                guard water.mass[i] > 0.02 else { continue }
                let d = hypot(Double(x)*c+c/2-p.x,Double(y)*c+Self.top+c/2-p.y)
                guard d < reach else { continue }
                let take = water.mass[i]*Float(min(0.9,1.15*(1-d/reach)))
                guard take > 0.01 else { continue }
                cells.append((i,take,d)); total += take
                setWater(i,water.mass[i]-take)
            }
        }
        // Water around the crater is woken too, so it pours into the hole the blast left.
        for y in max(0,cy-r-2)...min(Self.rows-1,cy+r+2) {
            for x in max(0,cx-r-2)...min(cols-1,cx+r+2) where water.mass[index(x,y)] > 0 { wakeWater(index(x,y)) }
        }
        guard total > 0 else { return }
        let column = depth >= 2
        let room = max(0,Self.maxWaterDrops-water.drops.count)
        let count = min(room,max(1,Int(total/0.12)),60+Int(radius*3))
        guard count > 0 else { for (i,take,_) in cells { pourWater(i,take) }; return }
        let each = total/Float(count)
        let power = min(1.6,radius/26)
        for k in 0..<count {
            let (i,_,d) = cells[k%cells.count]
            var from = Vec(x:(Double(i%cols)+water.random())*c,y:(Double(i/cols)+water.random())*c+Self.top)
            // Under the surface the water heaves up and bursts out through it above the shell.
            if column { from = Vec(x:p.x+(water.random()-0.5)*radius*1.3,y:p.y-Double(depth+1)*c-water.random()*c) }
            else {
                // Water thrown from below the surface leaves through it.
                var k = i
                while k >= cols && water.mass[k-cols] > 0.3 { k -= cols }
                if k != i { from.y = Double(k/cols)*c+Self.top-water.random()*c }
            }
            var dx = from.x-p.x, dy = from.y-p.y
            let len = max(1,hypot(dx,dy)); dx /= len; dy /= len
            let near = 1-min(1,d/reach)
            var v: Vec
            if column {
                v = Vec(x:dx*(40+water.random()*90)*power,y:-(200+water.random()*210+near*120)*power)
            } else {
                let s = (140+water.random()*240)*(0.5+near)*power
                v = Vec(x:dx*s,y:min(dy*s,0)-(90+water.random()*200)*power)
            }
            water.drops.append(WaterDrop(position:from,velocity:v,mass:each,life:5))
        }
        // White spray and a cloud of mist hang over the burst.
        let top = Vec(x:p.x,y:p.y-Double(depth)*c)
        for _ in 0..<min(40,8+count/2) where particles.count < 2800 {
            particles.append(Particle(position:top,velocity:Vec(x:(water.random()-0.5)*260*power,y:-water.random()*320*power),life:0.6+water.random()*0.7,total:1.3,kind:Self.sprayKind,size:1.2+water.random()*2))
        }
        for _ in 0..<min(14,4+count/6) where particles.count < 2800 {
            particles.append(Particle(position:top,velocity:Vec(x:(water.random()-0.5)*70,y:-20-water.random()*60*power),life:1.6+water.random()*1.6,total:3.2,kind:Self.mistKind,size:10+water.random()*16*power))
        }
    }
    /// Spray in the air falls back and pours into whatever it lands on.
    func updateWaterDrops(_ dt: Double) {
        guard !water.drops.isEmpty else { return }
        let c = Self.cell
        var flying: [WaterDrop] = []
        flying.reserveCapacity(water.drops.count)
        for var d in water.drops {
            d.life -= dt
            let steps = max(1,Int(hypot(d.velocity.x,d.velocity.y)*dt/3)+1)
            var landed = false
            for _ in 0..<steps {
                let sub = dt/Double(steps), before = d.position
                d.velocity.y += Self.gravity*sub
                d.velocity.x *= exp(-0.4*sub)
                d.position = d.position+d.velocity*sub
                if d.position.x < 0 || d.position.x >= Self.width || d.position.y >= Self.bottom { landed = true; break }
                guard d.position.y >= Self.top else { continue }
                let i = index(Int(d.position.x/c),Int((d.position.y-Self.top)/c))
                // It lands on a solid, or splashes down into standing water.
                if voxels[i] != 0 || (water.mass[i] > 0.3 && d.velocity.y > 0) {
                    let at = voxels[i] != 0 && before.y >= Self.top ? index(Int(before.x/c),Int((before.y-Self.top)/c)) : i
                    pourWater(at,d.mass)
                    if water.random() < 0.25 && particles.count < 2600 {
                        let s = min(1,hypot(d.velocity.x,d.velocity.y)/400)
                        particles.append(Particle(position:d.position,velocity:Vec(x:(water.random()-0.5)*80*s,y:-water.random()*110*s),life:0.3+water.random()*0.4,total:0.7,kind:Self.sprayKind,size:1+water.random()))
                    }
                    landed = true; break
                }
            }
            if !landed && d.life > 0 { flying.append(d) }
            else if !landed && d.position.y >= Self.top && d.position.y < Self.bottom && d.position.x >= 0 && d.position.x < Self.width {
                pourWater(index(Int(d.position.x/c),Int((d.position.y-Self.top)/c)),d.mass)
            }
        }
        water.drops = flying
    }
    /// A falling section ploughing through water shoves it aside and up, and is slowed by it.
    func chunkInWater(_ chunk: inout FallingChunk, _ dt: Double) {
        guard !water.rim.isEmpty || !water.active.isEmpty, chunk.cells.count > 0 else { return }
        let c = Self.cell, cols = Self.columns
        let stride = max(1,chunk.cells.count/48)
        var wet = 0
        let speed = hypot(chunk.velocity.x,chunk.velocity.y)
        for k in Swift.stride(from:0,to:chunk.cells.count,by:stride) where chunk.cells[k].edge {
            let p = chunk.point(chunk.cells[k])
            guard p.x >= 0 && p.x < Self.width && p.y >= Self.top && p.y < Self.bottom else { continue }
            let i = index(Int(p.x/c),Int((p.y-Self.top)/c))
            let m = water.mass[i]
            guard m > 0.15, voxels[i] == 0 else { continue }
            wet += 1
            guard speed > 25 else { continue }
            let take = m*Float(min(0.8,speed/300))
            setWater(i,m-take)
            guard water.drops.count < Self.maxWaterDrops else { pourWater(i-cols,take); continue }
            // Thrown out ahead of the section and up past its sides.
            let side = (water.random()-0.5)*2
            let v = Vec(x:chunk.velocity.x*0.7+side*(60+speed*0.5),y:-abs(chunk.velocity.y)*(0.4+water.random()*0.5)-60-water.random()*90)
            water.drops.append(WaterDrop(position:p,velocity:v,mass:take,life:4))
            if particles.count < 2600 && water.random() < 0.5 {
                particles.append(Particle(position:p,velocity:Vec(x:side*30,y:-15-water.random()*25),life:1.2+water.random(),total:2.2,kind:Self.mistKind,size:8+water.random()*10))
            }
        }
        if wet > 0 { chunk.velocity = chunk.velocity*exp(-1.6*dt*Double(min(wet,12))/12) }
    }
    /// A splash where a round passes through the surface.
    func ripple(at p: Vec, _ v: Vec) {
        guard particles.count < 2600 else { return }
        for _ in 0..<5 {
            particles.append(Particle(position:p,velocity:Vec(x:v.x*0.05+(water.random()-0.5)*60,y:-40-water.random()*90),life:0.3+water.random()*0.4,total:0.7,kind:Self.sprayKind,size:1+water.random()))
        }
    }
    /// Water in the cell at a world point, 0 outside the map.
    func waterAt(_ p: Vec) -> Float {
        guard p.x >= 0 && p.x < Self.width && p.y >= Self.top && p.y < Self.bottom else { return 0 }
        return water.mass[index(Int(p.x/Self.cell),Int((p.y-Self.top)/Self.cell))]
    }
    func resetWater() { seedWater() }
}
