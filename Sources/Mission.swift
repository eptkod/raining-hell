import Foundation

/// A high-value target: a region of infrastructure whose blocks pay extra and which
/// awards a bonus once enough of its original structure is gone.
struct Objective {
    let name: String
    /// Voxel bounds, half-open: x0..<x1, y0..<y1.
    let x0: Int, y0: Int, x1: Int, y1: Int
    let bonus: Int
    /// A bridge span: destroyed as soon as it is cut through, and then whatever still
    /// stands over the gorge falls into the river.
    var span = false
    var initial = 0
    var remaining = 0
    var destroyed = false
    /// Share of the original structure removed, 0...1.
    var damage: Double { initial == 0 ? 1 : 1-Double(remaining)/Double(initial) }
    var center: Vec {
        Vec(x:Double(x0+x1)/2*World.cell,y:Double(y0+y1)/2*World.cell+World.top)
    }
}
/// A line in the requisition menu: troops and what they cost.
struct TroopOffer {
    let name: String
    let detail: String
    let kind: TroopKind
    let count: Int
    let cost: Int
}
/// Floating score readout above an impact.
struct Popup { var position: Vec; var points: Int; var life: Double = 1.1; var major = false }

extension World {
    /// Points needed before the platoon may extract.
    static let requirement = 150_000
    /// Share of an objective's original structure that must be removed to destroy it.
    static let objectiveThreshold = 0.6
    /// Blocks inside a high-value target are worth this many times their base value.
    static let hvtMultiplier: UInt8 = 3
    /// Points per voxel: buildings matter, terrain barely does.
    static func points(_ m: UInt8) -> UInt8 {
        switch m {
        case 3, 5, 11, 12: return 10   // concrete, brick, steel, bridge
        case 4, 6, 7: return 5     // glass, sandbags, crates
        case 10: return 2          // rubble
        case 1, 2: return 1        // soil, rock
        default: return 0
        }
    }
    static func isStructure(_ m: UInt8) -> Bool { (m >= 3 && m <= 7) || m == 11 || m == 12 }
    /// Credits every round opens with, before any carried over from the last round.
    static let startingCredits = 2_000
    /// Share of a round's final points paid out as credits at the start of the next round:
    /// 150,000 points buys 6,000 credits.
    static let creditRate = 0.04
    static func credits(for points: Int) -> Int { Int((Double(max(0,points))*creditRate).rounded(.down)) }
    /// Share of a bank withdrawal lost on the way into an operation.
    static let withdrawalLoss = 0.25
    /// Credits that reach the field when `amount` is withdrawn from the bank.
    static func delivered(_ amount: Int) -> Int { amount-Int((Double(amount)*withdrawalLoss).rounded(.up)) }
    /// Moves up to `amount` from the bank into this round's credits, losing `withdrawalLoss`
    /// of it. Returns the credits that arrived.
    @discardableResult func withdraw(_ amount: Int) -> Int {
        let taken = max(0,min(amount,bank))
        let arrived = Self.delivered(taken)
        bank -= taken; credits += arrived; broughtCredits += arrived
        return arrived
    }
    /// World x range of the landing zone where troops may be placed.
    static let deployZone = 40.0...680.0
    static let offers = [TroopOffer(name:"RIFLEMAN",detail:"1 SOLDIER · LIGHT ROUNDS · FAST RELOAD",kind:.rifleman,count:1,cost:250),
                         TroopOffer(name:"GRENADIER",detail:"1 SOLDIER · HEAVY BLAST · SLOW RELOAD",kind:.grenadier,count:1,cost:750),
                         TroopOffer(name:"RIFLE SQUAD",detail:"4 RIFLEMEN · BULK RATE",kind:.rifleman,count:4,cost:900),
                         TroopOffer(name:"RPG GUNNER",detail:"1 SOLDIER · 7 ROCKETS · 7 S RELOAD · HAND-AIMED",kind:.rpg,count:1,cost:1200)]
    /// Points earned by destruction this round; extraction needs `requirement` of them.
    /// Spending never touches points: purchases come out of `credits`.
    var points: Int { score }
    var missionReady: Bool { points >= Self.requirement }
    /// Why an offer can't be bought right now, or nil if it can.
    func refusal(_ offer: TroopOffer) -> String? {
        if soldiers.count+offer.count > Self.maxSoldiers { return "PLATOON FULL" }
        return refusal(cost:offer.cost)
    }
    /// Why `cost` credits can't be spent right now, or nil if they can.
    func refusal(cost: Int) -> String? {
        cost > credits ? "NEED \(cost-credits) CR" : nil
    }
    /// Buys an offer and lands it at `x` inside the deployment zone.
    @discardableResult func purchase(_ offer: TroopOffer, at x: Double) -> Bool {
        guard Self.deployZone.contains(x) else { status = "OUTSIDE DEPLOYMENT ZONE · PLACE TROOPS IN THE LANDING ZONE"; return false }
        if let reason = refusal(offer) {
            switch reason {
            case "PLATOON FULL": status = "PLATOON LIMIT REACHED · \(Self.maxSoldiers) SOLDIERS"
            default: status = "REQUISITION DENIED · \(reason) FOR \(offer.name)"
            }
            onSound?(SoundEvent(cue:.cease))
            return false
        }
        credits -= offer.cost; spent += offer.cost
        spawn(offer.count,kind:offer.kind,at:x)
        status = "\(offer.name) DEPLOYED · -\(offer.cost) CR · CLICK A STRUCTURE TO ATTACK"
        return true
    }

    /// Lays out the objectives and per-voxel worth for the freshly built map.
    func setupMission() {
        let S = Self.scale
        func target(_ name: String,_ x0: Int,_ y0: Int,_ x1: Int,_ y1: Int,_ bonus: Int, span: Bool = false) -> Objective {
            Objective(name:name,x0:x0*S,y0:y0*S,x1:x1*S,y1:y1*S,bonus:bonus,span:span)
        }
        objectives = [target("OUTPOST BUNKER",108,24,152,58,1500),
                      // Only the deck over the gorge counts: dropping the span takes the bridge out,
                      // without digging out the abutments and footings buried in the banks.
                      target("KESSEL BRIDGE",262,Self.bridgeDeck,318,Self.bridgeDeck+2,5000,span:true),
                      target("CHURCH BELL TOWER",424,0,432,58,2000),
                      target("FUEL DEPOT & STACK",546,6,577,58,4000),
                      target("GUN EMPLACEMENT",667,24,686,33,3000),
                      target("TUNNEL DEPOT",600,38,700,49,4000)]
        worth = voxels.map { Self.points($0) }
        for i in objectives.indices {
            let o = objectives[i]
            for y in o.y0..<o.y1 {
                for x in o.x0..<o.x1 where Self.isStructure(voxels[index(x,y)]) { worth[index(x,y)] *= Self.hvtMultiplier }
            }
            objectives[i].initial = structureCount(o)
            objectives[i].remaining = objectives[i].initial
        }
        // The round's credits: the standing grant plus the payout for the last round's points.
        carriedCredits = Self.credits(for:score)
        credits = Self.startingCredits+carriedCredits; broughtCredits = 0; banked = 0
        score = 0; spent = 0; popups = []; missionClock = 0; extracted = false
    }
    func structureCount(_ o: Objective) -> Int {
        var count = 0
        for y in o.y0..<o.y1 { for x in o.x0..<o.x1 where Self.isStructure(voxels[index(x,y)]) { count += 1 } }
        return count
    }
    /// Width in voxels of the gap that must be blown clean through a span to bring it down.
    static let spanGap = 6*scale
    /// True once `spanGap` neighbouring columns of the span have no structure left.
    func spanCut(_ o: Objective) -> Bool {
        var run = 0
        for x in o.x0..<o.x1 {
            run = (o.y0..<o.y1).allSatisfy { !Self.isStructure(voxels[index(x,$0)]) } ? run+1 : 0
            if run >= Self.spanGap { return true }
        }
        return false
    }
    /// Brings down what is left of a cut span: the deck is parted from the abutments and
    /// the embankment lips it rests on, and the piers from their footings, so the
    /// structure solver drops it all into the river as rubble instead of leaving stubs
    /// overhanging the banks and pier walls that troops can't pass.
    func dropSpan(_ o: Objective) {
        let S = Self.scale
        func clear(_ x: Int, _ y: Int) {
            let i = index(x,y)
            if voxels[i] == 12 { voxels[i] = 0; worth[i] = 0 }
        }
        for x in o.x0..<o.x1 {
            let below = voxels[index(x,o.y1)]
            if x == o.x0 || x == o.x1-1 || below == 1 || below == 2 { for y in o.y0..<o.y1 { clear(x,y) } }
            clear(x,Self.riverBed*S-1)
        }
        structureDirty = true
    }
    /// Removes a voxel's worth from the map and returns it.
    func claim(_ i: Int) -> Int { defer { worth[i] = 0 }; return Int(worth[i]) }
    func award(_ points: Int, at p: Vec, major: Bool = false) {
        guard points > 0 else { return }
        let wasReady = missionReady
        score += points
        // Hits landing close together add up in one popup instead of stacking unreadably.
        if !major, let i = popups.lastIndex(where:{ !$0.major && $0.life > 0.5 && hypot($0.position.x-p.x,$0.position.y-p.y) < 60 }) {
            popups[i].points += points; popups[i].life = 1.1
        } else { popups.append(Popup(position:p,points:points,major:major)) }
        if popups.count > 48 { popups.removeFirst(popups.count-48) }
        if !wasReady && missionReady {
            onSound?(SoundEvent(cue:.select))
            status = "MISSION REQUIREMENT MET · PRESS X TO EXTRACT OR KEEP DESTROYING"
        }
    }
    func updateMission(_ dt: Double) {
        for i in popups.indices { popups[i].life -= dt; popups[i].position.y -= (popups[i].major ? 18 : 30)*dt }
        popups.removeAll { $0.life <= 0 }
        missionClock += dt
        guard missionClock >= 0.25 else { return }
        missionClock = 0
        for i in objectives.indices where !objectives[i].destroyed {
            objectives[i].remaining = structureCount(objectives[i])
            if objectives[i].damage >= Self.objectiveThreshold || (objectives[i].span && spanCut(objectives[i])) {
                objectives[i].destroyed = true
                if objectives[i].span { dropSpan(objectives[i]) }
                award(objectives[i].bonus,at:objectives[i].center,major:true)
                onSound?(SoundEvent(cue:.order,x:objectives[i].center.x))
                if !missionReady { status = "HVT DESTROYED · \(objectives[i].name) · +\(objectives[i].bonus) PTS" }
            }
        }
    }
    /// Ends the mission if the point requirement is met.
    @discardableResult func extract() -> Bool {
        guard missionReady else {
            status = "EXTRACTION DENIED · \(Self.requirement-points) MORE POINTS REQUIRED"
            return false
        }
        // Unspent credits go to the bank the first time the platoon extracts. Rounds that are
        // restarted or abandoned forfeit theirs, so the grant cannot be farmed into the bank.
        if !extracted { banked = credits; bank += credits; credits = 0 }
        extracted = true; paused = true
        status = "MISSION COMPLETE · PLATOON EXTRACTED"
        return true
    }
}
