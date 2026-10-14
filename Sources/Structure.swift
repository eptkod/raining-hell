import Foundation

/// A voxel riding a falling section: its offset from the section's centre, its
/// material, and the grid cell it left, so it can be drawn with its original texture.
struct RubbleCell { var x: Double; var y: Double; var material: UInt8; var gx = -1; var gy = -1; var edge = true }
struct FallingChunk {
    var id = 0
    /// The section this piece broke off from, whose texture it reuses.
    var parent = -1
    var position: Vec
    var velocity: Vec
    var angle: Double
    var spin: Double
    var cells: [RubbleCell]
    /// Distance from the centre to the farthest cell, for visibility culling.
    var radius = 0.0
    /// Where a section that tore off under load is still attached. It swings down
    /// about this point before snapping free and falling.
    var hinge: Vec? = nil
    var swing = 0.0
    /// How far (radians) the section swings about its hinge before it lets go. Torn slabs
    /// drop away early; a toppling building rides its hinge until it is nearly on its side.
    var release = 0.55
    /// Lean (radians) at which a toppling building snaps across its weakest storey.
    var snap: Double? = nil
    /// Whether the hinge is a toppling building's last bearing corner on standing
    /// structure, which holds through impacts, rather than a point it struck on landing.
    var rooted = false
    /// Times the section has struck and crumbled; only the first landing tips it onto its side.
    var landings = 0
    func point(_ cell: RubbleCell) -> Vec {
        Vec(x: position.x + cell.x*cos(angle)-cell.y*sin(angle),
            y: position.y + cell.x*sin(angle)+cell.y*cos(angle))
    }
}

extension World {
    /// Exposed reinforcing bars: horizontal ones from slabs and beams, vertical ones from
    /// walls and columns. They hold damaged concrete together but bear little weight.
    static let barH: UInt8 = 13, barV: UInt8 = 14
    static func isBar(_ m: UInt8) -> Bool { m == barH || m == barV }
    /// Sections smaller than this many voxels just fall; larger ones lean before they go.
    static let toppleMass = 40.0*Double(scale*scale)

    /// Casts reinforcing bars through the map's concrete, one cell in from each face: they run
    /// along slabs and beams and up walls and columns, every third cell in thick members.
    func layRebar() {
        let width = Self.columns, rows = Self.rows, n = voxels.count
        rebar = [UInt8](repeating:0,count:n)
        // Length of the unbroken concrete run through each cell, across and down.
        var across = [Int](repeating:0,count:n), down = [Int](repeating:0,count:n)
        for y in 0..<rows {
            var x = 0
            while x < width {
                guard voxels[index(x,y)] == 3 else { x += 1; continue }
                var end = x
                while end < width && voxels[index(end,y)] == 3 { end += 1 }
                for k in x..<end { across[index(k,y)] = end-x }
                x = end
            }
        }
        for x in 0..<width {
            var y = 0
            while y < rows {
                guard voxels[index(x,y)] == 3 else { y += 1; continue }
                var end = y
                while end < rows && voxels[index(x,end)] == 3 { end += 1 }
                for k in y..<end { down[index(x,k)] = end-y }
                y = end
            }
        }
        let thin = 2*Self.scale
        for y in 1..<(rows-1) {
            for x in 1..<(width-1) {
                let i = index(x,y)
                guard voxels[i] == 3 else { continue }
                if across[i] >= down[i] {
                    if voxels[i-width] == 3 && voxels[i+width] == 3 && (down[i] <= thin || y%3 == 0) { rebar[i] = Self.barH }
                } else if voxels[i-1] == 3 && voxels[i+1] == 3 && (across[i] <= thin || x%3 == 0) { rebar[i] = Self.barV }
            }
        }
    }

    /// Builds a falling section from grid cells, centred on them, and claims a chunk id.
    func section(_ ids: [Int], hinge: Vec? = nil) -> FallingChunk {
        let width = Self.columns, c = Self.cell
        func spot(_ i: Int) -> Vec { Vec(x:Double(i%width)*c+c/2,y:Double(i/width)*c+Self.top+c/2) }
        let center = Vec(x:ids.map{spot($0).x}.reduce(0,+)/Double(ids.count),y:ids.map{spot($0).y}.reduce(0,+)/Double(ids.count))
        let members = Set(ids)
        let cells = ids.map { i in
            let x = i%width, y = i/width
            let inner = x > 0 && x < width-1 && members.contains(i-1) && members.contains(i+1) && members.contains(i-width) && members.contains(i+width)
            return RubbleCell(x:spot(i).x-center.x,y:spot(i).y-center.y,material:voxels[i],gx:x,gy:y,edge:!inner)
        }
        chunkSerial += 1
        return FallingChunk(id:chunkSerial,position:center,velocity:Vec(x:0,y:0),angle:0,spin:0,cells:cells,radius:cells.map{hypot($0.x,$0.y)}.max() ?? 0,hinge:hinge)
    }

    /// Buildings tip over when their weight passes outside what holds them up. Working down
    /// the map one cut at a time, everything joined together above each cut is weighed
    /// against the run of cells bearing on the row below it. Weight hanging past the last
    /// bearing corner tries to turn the section about it; the bonded cells on the far side of
    /// the cut resist in tension, the more so the further they are from the corner. Plain
    /// concrete and brick hold little tension and rebar (even bare) a lot. When the turning
    /// wins, the whole section above the cut leans out about that corner, creaking over
    /// slowly at first, then snaps (see `snapped`) and falls on its side. The ground cannot
    /// hold anything down, so a section standing on it is only balanced by its own footprint.
    /// Returns whether anything began to topple.
    func toppleStructure() -> Bool {
        let width = Self.columns, n = voxels.count, S = Self.scale
        let voxels = self.voxels
        func member(_ m: UInt8) -> Bool { m == 3 || m == 4 || m == 5 || m == 11 || Self.isBar(m) }
        // Glass shatters and bare bars buckle, so neither bears weight from above.
        func bearing(_ m: UInt8) -> Bool { m == 1 || m == 2 || m == 3 || m == 5 || m == 11 || m == 12 }
        func terrain(_ m: UInt8) -> Bool { m == 1 || m == 2 }
        var parent = [Int32](repeating:-1,count:n)
        var mass = [Double](repeating:0,count:n), moment = [Double](repeating:0,count:n)
        var lo = [Int32](repeating:0,count:n), hi = [Int32](repeating:0,count:n), stamp = [Int32](repeating:-1,count:n)
        // A section found standing balanced on the ground passes its weight into it there,
        // so deeper cuts through footings and basements no longer carry it.
        var anchored = [Bool](repeating:false,count:n), grounded = [Int32](repeating:-1,count:n)
        func find(_ i: Int) -> Int {
            var i = i
            while Int(parent[i]) != i { parent[i] = parent[Int(parent[i])]; i = Int(parent[i]) }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            let (big,small) = mass[ra] >= mass[rb] ? (ra,rb) : (rb,ra)
            parent[small] = Int32(big); mass[big] += mass[small]; moment[big] += moment[small]
            anchored[big] = anchored[big] || anchored[small]
        }
        // Tension a bonded cell can hold across the cut, per voxel of lever arm.
        let rebar = self.rebar
        func tension(_ i: Int) -> Double {
            switch voxels[i] {
            case 3: return 60*Double(S)*(rebar[i] != 0 ? 1+reinforcement : 1)
            case 11: return 160*Double(S)
            case 5: return 16*Double(S)
            case Self.barH, Self.barV: return 60*Double(S)*reinforcement
            default: return 0
            }
        }
        var pull = [Double](repeating:0,count:n), pullMoment = [Double](repeating:0,count:n), pulled = [Int32](repeating:-1,count:n)
        var falls: [(row: Int, cell: Int, edge: Int)] = []
        for y in 0..<(Self.rows-1) {
            for x in 0..<width {
                let i = index(x,y), m = voxels[i]
                guard member(m) else { continue }
                parent[i] = Int32(i); mass[i] = m == 4 ? 0.2 : 1; moment[i] = mass[i]*(Double(x)+0.5)
                if x > 0 && parent[i-1] >= 0 { union(i,i-1) }
                if y > 0 && parent[i-width] >= 0 { union(i,i-width) }
            }
            // Cells passing weight down through the cut, or wedged against a bank beside it.
            var roots: [Int] = []
            for x in 0..<width {
                let i = index(x,y)
                guard parent[i] >= 0 else { continue }
                if member(voxels[i+width]) && voxels[i] != 4 && voxels[i+width] != 4 {
                    let r = find(i), t = tension(i)
                    if pulled[r] != Int32(y) { pulled[r] = Int32(y); pull[r] = 0; pullMoment[r] = 0 }
                    pull[r] += t; pullMoment[r] += t*(Double(x)+0.5)
                }
                guard bearing(voxels[i]) else { continue }
                let below = voxels[i+width], ground = (bearing(below) && !member(below)) || (x > 0 && terrain(voxels[i-1])) || (x < width-1 && terrain(voxels[i+1]))
                guard bearing(below) || ground else { continue }
                let r = find(i)
                if stamp[r] != Int32(y) { stamp[r] = Int32(y); lo[r] = Int32(x); roots.append(r) }
                hi[r] = Int32(x)
                if ground { grounded[r] = Int32(y) }
            }
            for r in roots where !anchored[r] {
                let com = moment[r]/mass[r], west = Double(lo[r]), east = Double(hi[r]+1)
                let t0 = pulled[r] == Int32(y) ? pull[r] : 0, t1 = pulled[r] == Int32(y) ? pullMoment[r] : 0
                if mass[r] >= Self.toppleMass && com < west && mass[r]*(west-com) > t1-west*t0 { falls.append((y,index(Int(lo[r]),y),Int(lo[r]))) }
                else if mass[r] >= Self.toppleMass && com > east && mass[r]*(com-east) > east*t0-t1 { falls.append((y,index(Int(hi[r]),y),Int(hi[r])+1)) }
                else if grounded[r] == Int32(y) { anchored[r] = true }
            }
        }
        guard !falls.isEmpty else { return false }
        // The lowest overbalanced cut takes everything above it, so it goes first.
        var taken = [Bool](repeating:false,count:n)
        var gained = 0, heaviest = 0, site = Vec(x:0,y:0)
        for fall in falls.sorted(by:{ $0.row > $1.row }) where !taken[fall.cell] {
            var piece = [fall.cell], next = 0
            taken[fall.cell] = true
            while next < piece.count {
                let i = piece[next], x = i%width
                next += 1
                for j in [x > 0 ? i-1 : -1, x < width-1 ? i+1 : -1, i-width, i+width] where j >= 0 && j/width <= fall.row && !taken[j] && member(voxels[j]) {
                    taken[j] = true; piece.append(j)
                }
            }
            let pivot = Vec(x:Double(fall.edge)*Self.cell,y:Double(fall.row+1)*Self.cell+Self.top)
            var chunk = section(piece,hinge:pivot)
            // Better reinforced frames bend further before they break.
            chunk.release = 1.3; chunk.snap = 0.3+0.08*reinforcement+random*0.12; chunk.rooted = true
            chunks.append(chunk)
            if piece.count > heaviest { heaviest = piece.count; site = chunk.position }
            for i in piece { gained += claim(i); self.voxels[i] = 0 }
            collapsed += piece.count
        }
        onSound?(SoundEvent(cue:.collapse,x:site.x))
        award(gained,at:site)
        quake(at:site,min(2,0.8+Double(heaviest)*0.004/Double(S*S)),cap:4,margin:80)
        return true
    }

    // Gameplay approximation: finite beam spans plus tributary loads on columns.
    // Glass is never part of a load path, but debris left with nothing else to stand on
    // rests on it until the pane gives way. Every solid tracks its overhang: how far
    // it sits sideways beyond a column that reaches the ground. Anything resting
    // on an overhang inherits it, so stacked ledges and buildings perched over a
    // crater fall once the total passes the material's reach.
    func solveStructure() {
        let toppled = toppleStructure()
        let n = voxels.count, width = Self.columns, S = Self.scale
        let voxels = self.voxels, rebar = self.rebar
        func reinforced(_ i: Int) -> Bool { voxels[i] == 3 && rebar[i] != 0 }
        // Rebar lets concrete span further, and exposed bars still bridge a gap.
        let rebarSpan = Int(Double(16*S)*(1+0.25*reinforcement))
        // Soil and rock rest on whatever solid is below them. Sideways cohesion only
        // lets a short overhang stand: reach is measured from the nearest resting
        // column, so an undercut slab falls however thick. Terrain whose column runs
        // to the map bottom through terrain is rooted and carries no structural load.
        func isTerrain(_ i: Int) -> Bool { voxels[i] == 1 || voxels[i] == 2 }
        func reach(_ i: Int) -> Int { (voxels[i] == 2 ? 5 : 3)*S }
        let unreached = Int.max/2
        var overhang = [Int](repeating:unreached,count:n)
        var grounded = [Bool](repeating:false,count:n)
        var rooted = [Bool](repeating:false,count:n)
        var supported = [Bool](repeating:false,count:n)
        // Each voxel passes its load to up to two anchors (-1 when unused).
        var anchorA = [Int](repeating:-1,count:n), anchorB = [Int](repeating:-1,count:n)
        for x in 0..<width {
            let i=index(x,Self.rows-1)
            if isTerrain(i) { overhang[i]=0; grounded[i]=true; rooted[i]=true; supported[i]=true }
        }
        for y in stride(from:Self.rows-2,through:0,by:-1) {
            // Direct supports are established before lateral beam propagation.
            var direct = [Bool](repeating:false,count:width)
            for x in 0..<width {
                let i=index(x,y), below=i+width
                guard isTerrain(i) && supported[below] else { continue }
                if isTerrain(below) { overhang[i]=overhang[below]; grounded[i]=grounded[below]; anchorA[i]=below }
                else { overhang[i]=overhang[below]; anchorA[i]=below }
                if overhang[i] < unreached { direct[x]=true }
            }
            for x in 1..<width {
                let i=index(x,y), j=i-1
                if isTerrain(i) && isTerrain(j) && overhang[j] < reach(j) && overhang[j]+1 < overhang[i] {
                    overhang[i]=overhang[j]+1; grounded[i]=grounded[j]
                }
            }
            for x in stride(from:width-2,through:0,by:-1) {
                let i=index(x,y), j=i+1
                if isTerrain(i) && isTerrain(j) && overhang[j] < reach(j) && overhang[j]+1 < overhang[i] {
                    overhang[i]=overhang[j]+1; grounded[i]=grounded[j]
                }
            }
            for x in 0..<width {
                let i=index(x,y), below=i+width
                if isTerrain(i) {
                    if overhang[i] <= reach(i) { supported[i]=true; rooted[i]=grounded[i] }
                } else if voxels[i] != 0 && voxels[i] != 4 && supported[below] && voxels[below] != 4 {
                    direct[x]=true; supported[i]=true; anchorA[i]=below; overhang[i]=overhang[below]
                }
            }
            for x in 0..<width {
                let i=index(x,y), m=voxels[i]
                if m == 0 || isTerrain(i) || direct[x] { continue }
                let span = reinforced(i) || Self.isBar(m) ? rebarSpan : (m == 12 ? 20 : m == 3 ? 16 : (m == 5 || m == 11 ? 9 : (m == 4 ? 10 : 0)))*S
                if span == 0 { continue }
                var found = 0, foundA = -1, foundB = -1, firstReach = unreached, minEnd = unreached
                for sign in [-1,1] {
                    for d in 1...span {
                        let nx=x+sign*d
                        if nx < 0 || nx >= width { break }
                        let j=index(nx,y)
                        if voxels[j] == 0 { break }
                        if m != 4 && voxels[j] == 4 { break }
                        if direct[nx] {
                            if found == 0 { foundA=j+width; firstReach=overhang[j]+d } else { foundB=j+width }
                            found += 1; minEnd=min(minEnd,overhang[j]); break
                        }
                    }
                }
                // A beam held at both ends adds no overhang; a cantilever adds its length.
                let reached = found == 2 ? minEnd : firstReach
                if found > 0 && (m == 4 || reached <= span) {
                    supported[i]=true; anchorA[i]=foundA; anchorB[i]=foundB; overhang[i]=reached
                }
                // Window panes can hang from their frame above or below.
                if m == 4 && (supported[i+width] || (y > 0 && voxels[i-width] == 3)) { supported[i]=true }
            }
            // Anything still unsupported that sits on a held pane rests its weight on it.
            for x in 0..<width {
                let i=index(x,y), below=i+width
                if voxels[i] != 0 && voxels[i] != 4 && !supported[i] && voxels[below] == 4 && supported[below] {
                    supported[i]=true; anchorA[i]=below; overhang[i]=overhang[below]
                }
            }
        }
        // Door lintels, short hanging wall sections, and glazing may hang from a
        // surviving beam. Limit the hanging depth so this cannot anchor a building.
        var hangingDepth = [Int](repeating:0,count:n)
        for y in 1..<Self.rows {
            for x in 0..<width {
                let i=index(x,y), m=voxels[i]
                if !supported[i] && (m == 3 || m == 4 || m == 5 || m == 11 || m == 12 || Self.isBar(m)) && supported[i-width] && hangingDepth[i-width] < 6*S {
                    supported[i]=true; hangingDepth[i]=hangingDepth[i-width]+1
                }
            }
        }
        var loads = [Double](repeating:0,count:n)
        var failed = [Bool](repeating:false,count:n)
        for y in 0..<(Self.rows-1) {
            for x in 0..<width {
                let i=index(x,y), m=voxels[i]
                if m == 0 || rooted[i] || !supported[i] { continue }
                loads[i] += m == 4 ? 0.2 : 1
                // Foundation concrete is reinforced and carries twice the load of ordinary slabs;
                // bridge concrete is heavier still. Glass holds a few cells of debris.
                // Rebar raises concrete's capacity; bare bars buckle under much of a load.
                let capacity = m == 4 ? 5*Double(S) : Self.isBar(m) ? 12*reinforcement*Double(S*S)
                    : (m == 12 ? (footings[i] ? 640.0 : 320) : m == 3 ? (footings[i] ? 440.0 : 220)*(reinforced(i) ? 1+0.5*reinforcement : 1) : (m == 5 || m == 11 ? 170 : 50))*Double(S*S)
                // Soil and rock compact rather than snap, so only building materials fail.
                if !isTerrain(i) && loads[i] > capacity { failed[i]=true; continue }
                let left=anchorA[i], right=anchorB[i]
                if left >= 0 && right < 0 { loads[left] += loads[i] }
                else if left >= 0 {
                    let a=abs(x-left%width), b=abs(x-right%width)
                    loads[left] += loads[i]*Double(b)/Double(max(1,a+b))
                    loads[right] += loads[i]*Double(a)/Double(max(1,a+b))
                }
            }
        }
        // A pane that cracks gives way whole.
        var panes = voxels.indices.filter{ failed[$0] && voxels[$0] == 4 }
        while let i = panes.popLast() {
            let x = i%width
            for j in [x > 0 ? i-1 : -1, x < width-1 ? i+1 : -1, i-width, i+width] where j >= 0 && j < n && voxels[j] == 4 && !failed[j] {
                failed[j]=true; panes.append(j)
            }
        }
        // Whatever bears only on a failed member tears away with it rather than waiting
        // to be found unsupported, so an overloaded section rips off in one go.
        var doomed = failed
        for y in stride(from:Self.rows-2,through:0,by:-1) {
            for x in 0..<width {
                let i=index(x,y), a=anchorA[i], b=anchorB[i]
                if !doomed[i] && a >= 0 && doomed[a] && (b < 0 || doomed[b]) { doomed[i]=true }
            }
        }
        // Everything that gives way and touches falls as one rigid piece, so a building
        // whose supports are cut drops whole and only crumbles when it lands.
        var loose = Set<Int>()
        for i in voxels.indices where voxels[i] != 0 && (!supported[i] || doomed[i]) { loose.insert(i) }
        var groups: [Int:[Int]] = [:]
        var seen = Set<Int>()
        for start in loose.sorted() where !seen.contains(start) {
            var piece = [start], next = 0
            seen.insert(start)
            while next < piece.count {
                let i = piece[next], x = i%width
                next += 1
                for j in [x > 0 ? i-1 : -1, x < width-1 ? i+1 : -1, i-width, i+width] where j >= 0 && j < n && loose.contains(j) && !seen.contains(j) {
                    seen.insert(j); piece.append(j)
                }
            }
            groups[start] = piece
        }
        if let first = groups.keys.sorted().first, let id = groups[first]?.first {
            onSound?(SoundEvent(cue:.collapse,x:Double(id%width)*Self.cell))
        }
        let c=Self.cell
        func spot(_ i: Int) -> Vec { Vec(x:Double(i%width)*c+c/2,y:Double(i/width)*c+Self.top+c/2) }
        func detach(_ ids: [Int], hinge: Vec?) {
            var chunk=section(ids,hinge:hinge)
            if ids.count > heaviest { heaviest=ids.count; site=chunk.position }
            // Large sections lean slowly instead of cartwheeling; torn sections start from rest.
            let heft=max(1,sqrt(Double(ids.count)/24))
            if hinge == nil { chunk.spin=(random-0.5)*1.2/heft; chunk.velocity.x=(random-0.5)*22/heft }
            chunks.append(chunk)
        }
        // Only building materials bond, so a torn section stays attached where it meets
        // surviving structure, never rubble or soil.
        func bonds(_ m: UInt8) -> Bool { m == 3 || m == 4 || m == 5 || m == 11 || m == 12 || Self.isBar(m) }
        // Rebar holds an unsupported overhang to the structure it hangs from, so it swings
        // down from there before snapping off instead of dropping straight away.
        func tied(_ i: Int, _ j: Int) -> Bool { reinforced(i) || reinforced(j) || Self.isBar(voxels[i]) || Self.isBar(voxels[j]) }
        var gained = 0, heaviest = 0, site = Vec(x:0,y:0)
        for key in groups.keys.sorted() {
            let ids=groups[key]!
            let torn=ids.filter{ failed[$0] }
            var joints: [Vec] = []
            for i in ids where bonds(voxels[i]) {
                let x=i%width
                for j in [x > 0 ? i-1 : -1, x < width-1 ? i+1 : -1, i-width, i+width] where j >= 0 && j < n && bonds(voxels[j]) && !loose.contains(j) && (!torn.isEmpty || (ids.count >= 6*S*S && tied(i,j))) {
                    joints.append((spot(i)+spot(j))*0.5)
                }
            }
            // A section of building only hangs from joints level with or above its middle. One
            // whose supports gave way beneath it drops straight down onto the floors below.
            // (A pane loaded with debris still tears and swings down from its frame.)
            if ids.filter({ voxels[$0] == 3 || voxels[$0] == 5 || voxels[$0] == 11 }).count*2 > ids.count {
                let middle=ids.map{ spot($0).y }.reduce(0,+)/Double(ids.count)
                joints.removeAll{ $0.y > middle+2*c }
            }
            if joints.isEmpty {
                detach(ids,hinge:nil)
            } else {
                // Like a hull breaking its back: held at both ends, the section splits where
                // it failed (or, for an overhang, down its middle) and each half swings down
                // from its own side.
                let crack=(torn.isEmpty ? ids : torn).map{spot($0).x}.reduce(0,+)/Double((torn.isEmpty ? ids : torn).count)
                let left=joints.filter{ $0.x < crack }, right=joints.filter{ $0.x >= crack }
                func mean(_ v: [Vec]) -> Vec { v.reduce(Vec(x:0,y:0)){$0+$1}*(1/Double(v.count)) }
                if left.isEmpty || right.isEmpty {
                    detach(ids,hinge:mean(joints))
                } else {
                    let west=ids.filter{ spot($0).x < crack }, east=ids.filter{ spot($0).x >= crack }
                    if !west.isEmpty { detach(west,hinge:mean(left)) }
                    if !east.isEmpty { detach(east,hinge:mean(right)) }
                }
            }
            // Bringing structure down scores as if it had been blasted. Settling rubble
            // scores nothing, so a pile that shifts again cannot be farmed for points.
            for i in ids { if voxels[i] != 10 { gained += claim(i) }; self.voxels[i]=0 }
            collapsed += ids.count
        }
        award(gained,at:site)
        // A building giving way rumbles as it starts to tumble, not only when it lands.
        let falling = groups.values.reduce(0){$0+$1.count}
        if falling > 0 { quake(at:site,min(2,0.8+Double(falling)*0.004/Double(Self.scale*Self.scale)),cap:4,margin:80) }
        // Rear panels require both floor and ceiling; a surviving foundation alone
        // cannot preserve a room-shaped backdrop after the building collapses.
        for i in backdrops.indices where backdrops[i] >= 0 {
            if self.voxels[backdrops[i]] != 3 || self.voxels[ceilings[i]] != 3 { backdrops[i] = -1 }
        }
        structureDirty = toppled || !groups.isEmpty
    }

    func updateChunks(_ dt:Double) {
        var moving: [FallingChunk] = []
        for var chunk in chunks {
            chunk.velocity.y += 460*dt
            let steps=max(1,Int(hypot(chunk.velocity.x,chunk.velocity.y)*dt/3)+1)
            var hit=false
            for _ in 0..<steps {
                let old=chunk, h=dt/Double(steps)
                if let pivot=chunk.hinge {
                    // Swing about the tear as a rigid body under gravity, then snap free
                    // carrying the swing's momentum.
                    let r=Vec(x:chunk.position.x-pivot.x,y:chunk.position.y-pivot.y)
                    chunk.spin += 460*r.x/max(1,chunk.radius*chunk.radius/3+r.x*r.x+r.y*r.y)*h
                    let turn=chunk.spin*h
                    let arm=Vec(x:r.x*cos(turn)-r.y*sin(turn),y:r.x*sin(turn)+r.y*cos(turn))
                    chunk.position=pivot+arm; chunk.angle += turn; chunk.swing += turn
                    chunk.velocity=Vec(x:-arm.y*chunk.spin,y:arm.x*chunk.spin)
                    // A piece left hanging straight down from its hinge tears loose and drops.
                    // A piece left hanging straight down from its hinge tears loose and drops, and
                    // one swinging back up against its own weight lets go rather than rocking.
                    if abs(chunk.swing) > chunk.release || (!chunk.rooted && ((abs(chunk.spin) < 0.02 && abs(arm.x) < Self.cell) || chunk.spin*arm.x < 0)) {
                        chunk.hinge=nil
                        if !chunk.rooted && chunk.spin*arm.x < 0 { chunk.spin *= 0.3 }
                    }
                } else {
                    chunk.position = chunk.position+chunk.velocity*h
                    chunk.angle += chunk.spin*h
                }
                var struck: [Int] = [], solid=false
                for cell in chunk.cells where cell.edge {
                    let p=chunk.point(cell)
                    // The torn edge grinds past the structure it ripped from.
                    if let pivot=old.hinge, hypot(p.x-pivot.x,p.y-pivot.y) < 12 { continue }
                    let probe=Vec(x:p.x,y:p.y+Self.cell*0.45)
                    if p.y >= Self.bottom-6 { solid=true; break }
                    guard blocksFall(at:probe) else { continue }
                    let i=index(Int(probe.x/Self.cell),Int((probe.y-Self.top)/Self.cell)), m=voxels[i]
                    // A building leaning over on its last corner bears down with its whole
                    // weight, crushing the wreckage of its lower floors rather than itself, and
                    // a heavy section dropping onto the storeys below pancakes through them.
                    let ground=m == 1 || m == 2 || m == 12 || footings[i]
                    if !ground && ((chunk.rooted && chunk.hinge != nil) || pancakes(chunk)) { struck.append(i) } else { solid=true; break }
                }
                if solid { let v=chunk.velocity; chunk=old; chunk.velocity=v; hit=true; break }
                if !struck.isEmpty {
                    let crushed=Set(struck).count
                    crush(struck)
                    if chunk.hinge != nil { chunk.spin *= 0.97 }
                    // Each floor it smashes through takes some of its speed, the more the lighter it is.
                    else { chunk.velocity=chunk.velocity*max(0.5,1-2*Double(crushed)/Double(chunk.cells.count)) }
                }
            }
            if hit {
                // The jolt of a leaning building's corner striking home snaps it.
                moving += chunk.snap != nil && chunk.hinge != nil ? snapped(chunk) : crumble(chunk)
            } else if let at=chunk.snap, chunk.hinge != nil, abs(chunk.swing) >= at {
                moving += snapped(chunk)
            } else if chunk.position.x > -60 && chunk.position.x < Self.width+60 { moving.append(chunk) }
        }
        chunks=moving
    }

    /// Whether a falling section is heavy and fast enough to crush the floors it lands on and
    /// carry on down, like a building in a controlled demolition. Lighter, slower or tumbling
    /// pieces stop and crumble on whatever they hit.
    func pancakes(_ chunk: FallingChunk) -> Bool {
        chunk.hinge == nil && Double(chunk.cells.count) >= 3*Self.toppleMass && chunk.velocity.y > 60 && chunk.velocity.y > abs(chunk.velocity.x)
            && abs(sin(2*chunk.angle)) < 0.5
    }

    /// Grinds cells a falling building bears down on into dust, scoring them as destroyed.
    func crush(_ cells: [Int]) {
        var gained=0
        for i in Set(cells) where voxels[i] != 0 {
            gained += claim(i); voxels[i]=0; destroyed += 1
            if particles.count < 900 && random < 0.3 {
                let p=Vec(x:(Double(i%Self.columns)+0.5)*Self.cell,y:(Double(i/Self.columns)+0.5)*Self.cell+Self.top)
                particles.append(Particle(position:p,velocity:Vec(x:(random-0.5)*50,y:-random*30),life:0.6+random*0.5,total:1.1,kind:9,size:5+random*6))
            }
        }
        if let i=cells.first { award(gained,at:Vec(x:Double(i%Self.columns)*Self.cell,y:Double(i/Self.columns)*Self.cell+Self.top)) }
        structureDirty=true
    }

    /// Whether a falling section strikes something at `p`. Exposed bars bend aside under
    /// the weight and are torn away rather than stopping it.
    func blocksFall(at p: Vec) -> Bool {
        let m=material(at:p)
        if Self.isBar(m) {
            let i=index(Int(p.x/Self.cell),Int((p.y-Self.top)/Self.cell))
            voxels[i]=0; worth[i]=0; structureDirty=true
            return false
        }
        return m != 0
    }

    /// A leaning building breaks across its weakest storey, the one with the least
    /// standing structure (usually a row of windows) near mid-height, once it has leant far
    /// enough or as soon as its corner strikes something. The part above
    /// flies free with the lean's momentum and keeps turning, so it lands on its side,
    /// while the rest rides its hinge on toward the ground.
    func snapped(_ chunk: FallingChunk) -> [FallingChunk] {
        var whole=chunk
        whole.snap=nil
        let S=Self.scale
        guard let pivot=chunk.hinge, let top=chunk.cells.map({$0.gy}).min(), let bottom=chunk.cells.map({$0.gy}).max(), bottom-top >= 18*S else { return [whole] }
        var strength=[Int](repeating:0,count:bottom-top+1)
        for cell in chunk.cells where cell.material != 4 { strength[cell.gy-top] += 1 }
        let mid=Double(top+bottom)/2
        let band=(top+(bottom-top)*3/10)...(top+(bottom-top)*7/10)
        guard let row=band.min(by:{ (strength[$0-top],abs(Double($0)-mid)) < (strength[$1-top],abs(Double($1)-mid)) }) else { return [whole] }
        func key(_ cell: RubbleCell) -> Int { cell.gy*Self.columns+cell.gx }
        // Re-centres a set of the section's cells as a piece of its own, moving with the
        // section's spin about the hinge.
        func piece(_ cells: [RubbleCell]) -> FallingChunk {
            let m=Vec(x:cells.map{$0.x}.reduce(0,+)/Double(cells.count),y:cells.map{$0.y}.reduce(0,+)/Double(cells.count))
            let members=Set(cells.map(key))
            let local=cells.map { cell -> RubbleCell in
                var cell=cell
                cell.x -= m.x; cell.y -= m.y
                let k=key(cell)
                cell.edge = ![k-1,k+1,k-Self.columns,k+Self.columns].allSatisfy{ members.contains($0) }
                return cell
            }
            let at=Vec(x:chunk.position.x+m.x*cos(chunk.angle)-m.y*sin(chunk.angle),y:chunk.position.y+m.x*sin(chunk.angle)+m.y*cos(chunk.angle))
            chunkSerial += 1
            var out=chunk
            out.id=chunkSerial; out.parent=chunk.id; out.position=at; out.cells=local; out.snap=nil
            out.radius=local.map{hypot($0.x,$0.y)}.max() ?? 0
            out.velocity=Vec(x:-(at.y-pivot.y)*chunk.spin,y:(at.x-pivot.x)*chunk.spin)
            return out
        }
        let lower=chunk.cells.filter{ $0.gy > row }
        var pieces: [FallingChunk]=lower.isEmpty ? [] : [piece(lower)]
        // What broke away above may come apart in more than one piece.
        let upper=chunk.cells.filter{ $0.gy <= row }
        var byKey: [Int:Int]=[:]
        for (n,cell) in upper.enumerated() { byKey[key(cell)]=n }
        var seen=[Bool](repeating:false,count:upper.count)
        for start in upper.indices where !seen[start] {
            var group=[start], at=0
            seen[start]=true
            while at < group.count {
                let k=key(upper[group[at]])
                for m in [k-1,k+1,k-Self.columns,k+Self.columns].compactMap({ byKey[$0] }) where !seen[m] { seen[m]=true; group.append(m) }
                at += 1
            }
            // When the storeys below stop short, the top is flung on over.
            var free=piece(group.map{ upper[$0] })
            free.hinge=nil; free.rooted=false; free.spin=chunk.spin*1.5
            pieces.append(free)
        }
        // Dust bursts out along the break.
        for cell in chunk.cells where cell.gy == row && particles.count < 900 && random < 0.3 {
            particles.append(Particle(position:chunk.point(cell),velocity:Vec(x:(random-0.5)*60,y:-random*30),life:0.7+random*0.6,total:1.3,kind:9,size:6+random*8))
        }
        onSound?(SoundEvent(cue:.collapse,x:chunk.position.x))
        quake(at:chunk.position,min(2,0.5+Double(chunk.cells.count)*0.002/Double(S*S)),cap:4,margin:80)
        return pieces
    }

    /// A falling section breaks up where it strikes: cells near the contact crumble to
    /// rubble that drops to the ground, and the rest falls on as one or more smaller
    /// pieces. Rubble cannot hold masonry up, so a piece landing on its own debris
    /// keeps crumbling until nothing is left.
    func crumble(_ chunk: FallingChunk) -> [FallingChunk] {
        let c=Self.cell, S=Self.scale
        func key(_ cell: RubbleCell) -> Int { cell.gy*Self.columns+cell.gx }
        var byKey: [Int:Int] = [:]
        for (n,cell) in chunk.cells.enumerated() { byKey[key(cell)]=n }
        func neighbours(_ n: Int) -> [Int] {
            let k=key(chunk.cells[n])
            return [k-1,k+1,k-Self.columns,k+Self.columns].compactMap{ byKey[$0] }
        }
        // Cells resting on (or pressed into) something solid are the contact patch.
        var contact=chunk.cells.indices.filter { n in
            let cell=chunk.cells[n]
            guard cell.edge else { return false }
            let p=chunk.point(cell)
            return p.y >= Self.bottom-6-c || blocksFall(at:Vec(x:p.x,y:p.y+c*0.45)) || blocksFall(at:Vec(x:p.x,y:p.y+c*1.2))
        }
        if contact.isEmpty, let low=chunk.cells.map({ chunk.point($0).y }).max() {
            contact=chunk.cells.indices.filter{ chunk.point(chunk.cells[$0]).y > low-c }
        }
        let touch=contact.map{ chunk.point(chunk.cells[$0]) }
        // Harder impacts shatter deeper into the section.
        let speed=hypot(chunk.velocity.x,chunk.velocity.y)
        // A heavy section caves in the roof or wreckage it lands on, but not the ground.
        let heft=Double(chunk.cells.count)/Self.toppleMass
        if heft >= 1 {
            let reach=min(4*S,Int(speed/60*heft.squareRoot()))
            var caved: [Int]=[]
            for p in touch where reach > 0 {
                let x=Int(p.x/c)
                guard x >= 0 && x < Self.columns else { continue }
                for d in 0..<reach {
                    let y=Int((p.y+c*(0.45+Double(d))-Self.top)/c)
                    guard y >= 0 && y < Self.rows else { break }
                    let m=voxels[index(x,y)]
                    if m == 1 || m == 2 || m == 12 { break }
                    if m != 0 { caved.append(index(x,y)) }
                }
            }
            if !caved.isEmpty { crush(caved) }
        }
        let depth=chunk.cells.count <= 3*S*S ? Int.max : min(8*S,S+Int(speed/70))
        var crushed=[Int](repeating:-1,count:chunk.cells.count)
        var queue=contact
        for n in queue { crushed[n]=0 }
        var next=0
        while next < queue.count {
            let n=queue[next]; next += 1
            if crushed[n] >= depth { continue }
            for m in neighbours(n) where crushed[m] < 0 { crushed[m]=crushed[n]+1; queue.append(m) }
        }
        // Crumbled cells settle straight down onto whatever lies below them.
        var broken=0
        for n in chunk.cells.indices.filter({ crushed[$0] >= 0 }).sorted(by:{chunk.point(chunk.cells[$0]).y > chunk.point(chunk.cells[$1]).y}) {
            let cell=chunk.cells[n], p=chunk.point(cell)
            let x=max(0,min(Self.columns-1,Int(p.x/c)))
            var y=max(0,min(Self.rows-1,Int((p.y-Self.top)/c)))
            while y > 0 && material(x,y) != 0 { y -= 1 }
            while y < Self.rows-1 && material(x,y+1) == 0 { y += 1 }
            // Building materials crumble to rubble; soil and rock stay as they are.
            if material(x,y) == 0 {
                let terrain = cell.material == 1 || cell.material == 2
                // Fallen terrain was already scored; rubble is worth a little to clear.
                voxels[index(x,y)] = terrain ? cell.material : 10
                worth[index(x,y)] = terrain ? 0 : Self.points(10)
            }
            broken += 1
            if broken%4 == 0 && particles.count < 900 {
                particles.append(Particle(position:p,velocity:Vec(x:(random-0.5)*65,y:-random*42),life:0.6+random*0.5,total:1.1,kind:9,size:6+random*7))
            }
        }
        structureDirty=true
        if broken >= 6*S*S || random < 0.25 { onSound?(SoundEvent(cue:.rubble,x:chunk.position.x,gain:min(1,0.35+Double(broken)/Double(60*S*S)))) }
        quake(at:chunk.position,Double(broken)*0.03/Double(S*S),cap:3,margin:40)
        // Whatever survived splits into the pieces that still hold together.
        var pieces: [FallingChunk] = []
        var seen=crushed.map{ $0 >= 0 }
        for start in chunk.cells.indices where !seen[start] {
            var group=[start], at=0
            seen[start]=true
            while at < group.count {
                for m in neighbours(group[at]) where !seen[m] { seen[m]=true; group.append(m) }
                at += 1
            }
            let members=Set(group.map{ key(chunk.cells[$0]) })
            var cells=group.map{ chunk.cells[$0] }
            for i in cells.indices {
                let k=key(cells[i])
                cells[i].edge = ![k-1,k+1,k-Self.columns,k+Self.columns].allSatisfy{ members.contains($0) }
            }
            chunkSerial += 1
            // The blow knocks most of the speed out and sets the piece tipping.
            pieces.append(FallingChunk(id:chunkSerial,parent:chunk.id,position:chunk.position,
                                       velocity:Vec(x:chunk.velocity.x*0.5+(random-0.5)*12,y:min(chunk.velocity.y*0.25,60)),
                                       angle:chunk.angle,spin:chunk.spin*0.6+(random-0.5)*0.5/max(1,sqrt(Double(cells.count)/24)),
                                       cells:cells,radius:cells.map{hypot($0.x,$0.y)}.max() ?? 0))
        }
        for k in pieces.indices { pieces[k].landings=chunk.landings+1 }
        guard let main=pieces.indices.max(by:{ pieces[$0].cells.count < pieces[$1].cells.count }) else { return pieces }
        if let pivot=chunk.hinge, chunk.rooted {
            // A toppling building crushes the corner it leans onto and keeps turning about its
            // hinge, so it goes on over rather than settling at an angle.
            pieces[main].hinge=pivot; pieces[main].swing=chunk.swing; pieces[main].release=chunk.release
            pieces[main].snap=chunk.snap; pieces[main].rooted=true; pieces[main].spin=chunk.spin*0.85
        } else if chunk.landings == 0 && pieces[main].cells.count >= Int(Self.toppleMass) && !touch.isEmpty {
            // A large piece landing on one corner tips over about it onto its side.
            let piece=pieces[main]
            let m=Vec(x:piece.cells.map{$0.x}.reduce(0,+)/Double(piece.cells.count),y:piece.cells.map{$0.y}.reduce(0,+)/Double(piece.cells.count))
            let center=Vec(x:piece.position.x+m.x*cos(piece.angle)-m.y*sin(piece.angle),y:piece.position.y+m.x*sin(piece.angle)+m.y*cos(piece.angle))
            let corner=Vec(x:touch.map{$0.x}.reduce(0,+)/Double(touch.count),y:(touch.map{$0.y}.max() ?? 0)+c/2)
            if abs(center.x-corner.x) > max(2*c,piece.radius*0.25) {
                pieces[main].position=center
                pieces[main].cells=piece.cells.map{ var cell=$0; cell.x -= m.x; cell.y -= m.y; return cell }
                pieces[main].radius=pieces[main].cells.map{hypot($0.x,$0.y)}.max() ?? 0
                pieces[main].hinge=corner; pieces[main].swing=0; pieces[main].release=1.2; pieces[main].spin=chunk.spin*0.7
            }
        }
        return pieces
    }
}
