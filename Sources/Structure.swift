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
    func point(_ cell: RubbleCell) -> Vec {
        Vec(x: position.x + cell.x*cos(angle)-cell.y*sin(angle),
            y: position.y + cell.x*sin(angle)+cell.y*cos(angle))
    }
}

extension World {
    // Gameplay approximation: finite beam spans plus tributary loads on columns.
    // Glass is never part of a load path, but debris left with nothing else to stand on
    // rests on it until the pane gives way. Every solid tracks its overhang: how far
    // it sits sideways beyond a column that reaches the ground. Anything resting
    // on an overhang inherits it, so stacked ledges and buildings perched over a
    // crater fall once the total passes the material's reach.
    func solveStructure() {
        let n = voxels.count, width = Self.columns, S = Self.scale
        let voxels = self.voxels
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
                let span = (m == 12 ? 20 : m == 3 ? 16 : (m == 5 || m == 11 ? 9 : (m == 4 ? 10 : 0)))*S
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
                if !supported[i] && (m == 3 || m == 4 || m == 5 || m == 11 || m == 12) && supported[i-width] && hangingDepth[i-width] < 6*S {
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
                let capacity = m == 4 ? 5*Double(S) : (m == 12 ? (footings[i] ? 640.0 : 320) : m == 3 ? (footings[i] ? 440.0 : 220) : (m == 5 || m == 11 ? 170 : 50))*Double(S*S)
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
            let center=Vec(x:ids.map{spot($0).x}.reduce(0,+)/Double(ids.count),y:ids.map{spot($0).y}.reduce(0,+)/Double(ids.count))
            let members=Set(ids)
            let cells=ids.map { i in
                let x=i%width, y=i/width
                let inner = x > 0 && x < width-1 && members.contains(i-1) && members.contains(i+1) && members.contains(i-width) && members.contains(i+width)
                return RubbleCell(x:spot(i).x-center.x,y:spot(i).y-center.y,material:voxels[i],gx:x,gy:y,edge:!inner)
            }
            if ids.count > heaviest { heaviest=ids.count; site=center }
            // Large sections lean slowly instead of cartwheeling; torn sections start from rest.
            let heft=max(1,sqrt(Double(ids.count)/24))
            let spin=hinge == nil ? (random-0.5)*1.2/heft : 0
            let drift=hinge == nil ? (random-0.5)*22/heft : 0
            chunkSerial += 1
            chunks.append(FallingChunk(id:chunkSerial,position:center,velocity:Vec(x:drift,y:0),angle:0,spin:spin,cells:cells,radius:cells.map{hypot($0.x,$0.y)}.max() ?? 0,hinge:hinge))
        }
        // Only building materials bond, so a torn section stays attached where it meets
        // surviving structure, never rubble or soil.
        func bonds(_ m: UInt8) -> Bool { m == 3 || m == 4 || m == 5 || m == 11 || m == 12 }
        var gained = 0, heaviest = 0, site = Vec(x:0,y:0)
        for key in groups.keys.sorted() {
            let ids=groups[key]!
            let torn=ids.filter{ failed[$0] }
            var joints: [Vec] = []
            if !torn.isEmpty {
                for i in ids where bonds(voxels[i]) {
                    let x=i%width
                    for j in [x > 0 ? i-1 : -1, x < width-1 ? i+1 : -1, i-width, i+width] where j >= 0 && j < n && bonds(voxels[j]) && !loose.contains(j) {
                        joints.append((spot(i)+spot(j))*0.5)
                    }
                }
            }
            if joints.isEmpty {
                detach(ids,hinge:nil)
            } else {
                // Like a hull breaking its back: held at both ends, the section splits where
                // it failed and each half swings down from its own side.
                let crack=torn.map{spot($0).x}.reduce(0,+)/Double(torn.count)
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
        structureDirty = !groups.isEmpty
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
                    if abs(chunk.swing) > 0.55 { chunk.hinge=nil }
                } else {
                    chunk.position = chunk.position+chunk.velocity*h
                    chunk.angle += chunk.spin*h
                }
                if chunk.cells.contains(where:{ cell in
                    guard cell.edge else { return false }
                    let p=chunk.point(cell)
                    // The torn edge grinds past the structure it ripped from.
                    if let pivot=old.hinge, hypot(p.x-pivot.x,p.y-pivot.y) < 12 { return false }
                    return p.y >= Self.bottom-6 || material(at:Vec(x:p.x,y:p.y+Self.cell*0.45)) != 0
                }) { let v=chunk.velocity; chunk=old; chunk.velocity=v; hit=true; break }
            }
            if hit {
                moving += crumble(chunk)
            } else if chunk.position.x > -60 && chunk.position.x < Self.width+60 { moving.append(chunk) }
        }
        chunks=moving
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
            return p.y >= Self.bottom-6-c || material(at:Vec(x:p.x,y:p.y+c*0.45)) != 0 || material(at:Vec(x:p.x,y:p.y+c*1.2)) != 0
        }
        if contact.isEmpty, let low=chunk.cells.map({ chunk.point($0).y }).max() {
            contact=chunk.cells.indices.filter{ chunk.point(chunk.cells[$0]).y > low-c }
        }
        // Harder impacts shatter deeper into the section.
        let speed=hypot(chunk.velocity.x,chunk.velocity.y)
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
        return pieces
    }
}
