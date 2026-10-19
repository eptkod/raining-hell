import Foundation

/// Off-map support the requisition menu's SUPPORT tab can call in.
enum SupportKind { case supplyCrate, gunRun, firebomb, drone }
/// A line in the SUPPORT tab: what is called in and what it costs.
struct SupportOffer {
    let name: String
    let detail: String
    let kind: SupportKind
    let cost: Int
}
/// An airdropped ammo crate. It leaves the plane carrying the plane's speed, slows and
/// drifts down under a parachute, settles on whatever is below it, and refills every
/// soldier within `World.crateRadius` from its limited stock until it runs dry or expires.
struct SupplyCrate {
    var position: Vec
    var landed = false
    var life = World.crateLife
    /// Rounds left to hand out; enough for `World.crateLoads` full rifleman loads.
    var stock = World.crateStock
    /// Forward speed left over from the plane, bled off by the parachute.
    var drift = 0.0
}
/// A cargo plane crossing the whole sky from the map edge nearer `dropX` to drop a crate there.
struct SupplyPlane {
    var x: Double
    /// Current height; it follows `World.transportAltitude` as the skyline changes.
    var y: Double
    let dropX: Double
    /// +1 flying east (in from the west edge), -1 flying west (in from the east edge).
    var heading = 1.0
    var dropped = false
}

/// A ground-attack jet making one strafing pass in from the map edge nearer `targetX`: it
/// dives on the target, walks a burst of cannon rounds through `World.strafeLength` px of
/// ground centred there, then pulls up and leaves. Its height follows `World.strafePath`.
struct StrafeJet {
    var x: Double
    let targetX: Double
    /// Lowest point of the dive, chosen at call-in to clear the skyline under the pass.
    let low: Double
    /// Cruising height before and after the dive, set at call-in from the skyline.
    let cruise: Double
    /// +1 flying east (in from the west edge), -1 flying west (in from the east edge).
    var heading = 1.0
    var fired = 0
    /// Seconds left on the muzzle flash after the last round.
    var flash = 0.0
    /// Distance travelled past the target along the jet's heading.
    var dx: Double { (x-targetX)*heading }
    /// Height and pitch at the jet's current point on its pass.
    var path: (y: Double, pitch: Double) { World.strafePath(dx,low:low,cruise:cruise) }
}

extension World {
    static let support = [SupportOffer(name:"SUPPLY CRATE",detail:"AIRDROP · AMMO FOR 10 RIFLEMEN · LASTS 45 S",kind:.supplyCrate,cost:150),
                          SupportOffer(name:"GUN RUN",detail:"STRAFING PASS · 30MM BURST WALKED ACROSS 480 PX",kind:.gunRun,cost:1000),
                          SupportOffer(name:"FIREBOMBS",detail:"C-130 · 8 NAPALM CANISTERS · LONG-BURNING FIRES",kind:.firebomb,cost:2000),
                          SupportOffer(name:"KAMIKAZE DRONE",detail:"QUADCOPTER · YOU PILOT IT WITH THE POINTER · 20 S BATTERY",kind:.drone,cost:World.droneCost)]
    /// Reach of a landed crate, in world px from its centre.
    static let crateRadius = 120.0
    /// Seconds a landed crate keeps rearming troops.
    static let crateLife = 45.0
    /// Full rifleman loads packed in each crate; grenadiers draw from the same rounds.
    static let crateLoads = 10
    static var crateStock: Int { crateLoads*TroopKind.rifleman.magazine }
    static let crateFallSpeed = 170.0
    /// Height of the transports' centre line above the tallest standing block. Their landing
    /// gear and lowered ramp hang 24 px below it, so this leaves a wide gap over every roof.
    static let flightClearance = 455.0
    /// Open sky the camera may rise into above the map.
    static let skyHeight = 620.0
    /// Highest the aircraft fly, so the transport's tail fin stays where the camera can reach.
    static let flightCeiling = World.top-skyHeight+60
    /// The strafing jet cruises this far above the transports.
    static let jetStack = 90.0
    /// Climb or descent rate (px/s) of a transport following a changing skyline.
    static let climbRate = 45.0
    /// Seconds between skyline measurements.
    static let skylineInterval = 0.5
    /// Cruising height for transports: well clear of the tallest block still standing, so
    /// they fly lower once a tower comes down.
    var transportAltitude: Double { max(Self.flightCeiling,skyline-Self.flightClearance) }
    /// Cruising height for a strafing jet called in now.
    var jetCruise: Double { max(Self.flightCeiling-30,transportAltitude-Self.jetStack) }
    /// Measures the top of the tallest block on the map.
    func refreshSkyline() {
        skyline = stride(from:0.0,to:Self.width,by:Self.cell).map{ ground(at:$0) }.min() ?? Self.top
    }
    /// The crate leaves through the rear cargo ramp, this far behind the plane's centre.
    static let rampOffset = 66.0
    static let planeSpeed = 520.0
    /// Least distance short of its drop point a plane appears, so a drop near the map edge
    /// still shows the plane flying in with its ramp lowering.
    static let planeRun = 700.0
    /// How far beyond the map edge aircraft appear and leave.
    static let edgeMargin = 220.0
    /// Aircraft come in from whichever map edge is nearer the point they are called on.
    static func heading(toward x: Double) -> Double { x < width/2 ? 1 : -1 }
    /// Heading of support called on `x`: the player's chosen side (`supportSide`) if set,
    /// otherwise in from the nearer edge.
    func approach(toward x: Double) -> Double { supportSide ?? Self.heading(toward:x) }
    /// Where an aircraft heading `heading` enters: off the near map edge, or further out if
    /// it needs at least `lead` px of run-up before reaching `x`.
    static func entry(_ heading: Double, toward x: Double, lead: Double) -> Double {
        heading > 0 ? min(-edgeMargin,x-lead) : max(width+edgeMargin,x+lead)
    }
    /// Whether an aircraft at `x` heading `heading` has flown off the far side of the map.
    static func departed(_ x: Double, heading: Double) -> Bool {
        heading > 0 ? x > width+edgeMargin : x < -edgeMargin
    }
    /// Map x clamped onto the map, for placing an aircraft's sound while it is still off it.
    static func onMap(_ x: Double) -> Double { max(0,min(width,x)) }
    /// Rate (per second) at which a crate's parachute bleeds off the plane's speed.
    static let crateDrag = 2.5
    /// The plane releases this far short of the drop point so the drifting crate lands on it.
    static var releaseLead: Double { planeSpeed/crateDrag }
    static let jetSpeed = 900.0
    /// Width of ground the burst is walked across, centred on the called-in point.
    static let strafeLength = 480.0
    static let gunRounds = 120
    static let gunMuzzleSpeed = 1500.0
    static let gunBlastRadius = 12.0
    /// Rounds self-destruct this far past the far end of the strip.
    static let gunFuseReach = 12.0
    /// The gun fires while the jet is this far (relative to the target) along its pass.
    static let fireWindow = -700.0 ... -200.0
    /// Along its pass, the jet is at least this far short of the target when it appears,
    /// starts its dive at `diveStart`, levels out at `diveEnd`, and is back at cruise
    /// height by `climbEnd`; it then flies on off the far side of the map.
    static let jetEntry = -2000.0, diveStart = -1400.0, diveEnd = -150.0, climbEnd = 450.0
    /// Gun muzzle position relative to the jet's centre, before pitch is applied.
    static let gunMuzzle = Vec(x:56,y:2)
    /// Height and pitch (radians, positive nose-down) of a strafing jet `dx` px past its target.
    static func strafePath(_ dx: Double, low: Double, cruise: Double) -> (y: Double, pitch: Double) {
        let jetAltitude = cruise, drop = low-jetAltitude
        if dx <= diveStart { return (jetAltitude,0) }
        if dx <= diveEnd {
            // A straight dive, eased in over its first 200 px.
            let span = diveEnd-diveStart, ease = min(1,(dx-diveStart)/200)
            let slope = drop/(span-100)
            let y = dx-diveStart < 200 ? jetAltitude+slope*(dx-diveStart)*(dx-diveStart)/400 : jetAltitude+slope*(dx-diveStart-100)
            return (y,atan(slope*ease))
        }
        if dx < climbEnd {
            let t = (dx-diveEnd)/(climbEnd-diveEnd), slope = drop/(diveEnd-diveStart-100)
            // Cubic that leaves the dive at its slope and levels off at cruise height.
            let span = climbEnd-diveEnd, m0 = slope*span
            let h00 = 2*t*t*t-3*t*t+1, h10 = t*t*t-2*t*t+t, h01 = -2*t*t*t+3*t*t
            let y = h00*low+h10*m0+h01*jetAltitude
            let d = ((6*t*t-6*t)*low+(3*t*t-4*t+1)*m0+(-6*t*t+6*t)*jetAltitude)/span
            return (y,atan(d))
        }
        return (jetAltitude,0)
    }
    /// Where a strafing jet's cannon is, given its position along the pass.
    static func gunPosition(_ jet: StrafeJet) -> Vec {
        let (y,pitch) = jet.path, m = gunMuzzle
        return Vec(x:jet.x+jet.heading*(m.x*cos(pitch)-m.y*sin(pitch)),y:y+m.x*sin(pitch)+m.y*cos(pitch))
    }
    /// The lowest the jet may dive over `x`: well clear of every block under the low part of
    /// its pass, and raised further if the dive or climb-out would clip a tower on the way.
    func strafeFloor(_ x: Double) -> Double {
        var top = Self.bottom
        let h = approach(toward:x), a = x+h*(Self.diveEnd-150), b = x+h*(Self.strafeLength/2+30)
        for px in stride(from:min(a,b),through:max(a,b),by:Self.cell) { top = min(top,ground(at:px)) }
        let cruise = jetCruise, ceiling = cruise+40
        var low = max(ceiling,min(top-110,ground(at:x)-230))
        func clips(_ low: Double) -> Bool {
            stride(from:Self.diveStart,through:Self.climbEnd,by:Self.cell).contains { dx in
                Self.strafePath(dx,low:low,cruise:cruise).y+Self.jetClearance > ground(at:x+h*dx)
            }
        }
        while low > ceiling && clips(low) { low = max(ceiling,low-Self.cell) }
        return low
    }
    /// Gap kept between the jet's centre line and any block beneath its dive and climb-out.
    static let jetClearance = 40.0
    /// Seconds before another gun run can be called, counted from the call-in.
    static let gunRunCooldown = 30.0

    /// Seconds left before an offer can be called again; supply crates have no cooldown.
    func cooldown(_ kind: SupportKind) -> Double {
        if devMode { return 0 }
        switch kind {
        case .supplyCrate: return 0
        case .gunRun: return gunRunCooldown
        case .firebomb: return firebombCooldown
        case .drone: return droneCooldown
        }
    }
    /// Why a support call can't be bought right now, or nil if it can.
    func refusal(_ offer: SupportOffer) -> String? {
        let wait = cooldown(offer.kind)
        if wait > 0 { return "COOLDOWN \(Int(wait.rounded(.up)))S" }
        if offer.kind == .drone && drone != nil { return "DRONE AIRBORNE" }
        return refusal(cost:offer.cost)
    }
    /// Calls in support at world x. Supply crates may land anywhere on the map.
    @discardableResult func purchase(_ offer: SupportOffer, at x: Double) -> Bool {
        guard x >= 0 && x <= Self.width else { return false }
        if let reason = refusal(offer) {
            let wait = cooldown(offer.kind)
            status = reason == "DRONE AIRBORNE" ? "ONE DRONE AT A TIME · DETONATE THE ONE IN THE AIR FIRST" : wait > 0 ? "\(offer.name) ON COOLDOWN · READY IN \(Int(wait.rounded(.up)))S"
                : "SUPPORT DENIED · \(reason) FOR \(offer.name)"
            onSound?(SoundEvent(cue:.cease))
            return false
        }
        if !devMode { credits -= offer.cost }; spent += offer.cost
        refreshSkyline()
        switch offer.kind {
        case .supplyCrate:
            let h = approach(toward:x)
            let plane = SupplyPlane(x:Self.entry(h,toward:x,lead:Self.planeRun),y:transportAltitude,dropX:x,heading:h)
            planes.append(plane)
            onSound?(SoundEvent(cue:.plane,x:Self.onMap(plane.x)))
            status = "SUPPLY PLANE INBOUND · -\(offer.cost) CR · MOVE TROOPS INTO THE DROP RING TO REARM"
        case .gunRun:
            gunRunCooldown = Self.gunRunCooldown
            let h = approach(toward:x)
            let jet = StrafeJet(x:Self.entry(h,toward:x,lead:-Self.jetEntry),targetX:x,low:strafeFloor(x),cruise:jetCruise,heading:h)
            jets.append(jet)
            onSound?(SoundEvent(cue:.jet,x:Self.onMap(jet.x)))
            status = "GUN RUN INBOUND · -\(offer.cost) CR · STRAFING THE MARKED STRIP"
        case .firebomb:
            firebombCooldown = Self.firebombCooldown
            let h = approach(toward:x)
            let aims = h > 0 ? Self.firebombAims(x) : Self.firebombAims(x).reversed()
            // From the near map edge, so the plane is heard and seen well before the first release.
            let alt = transportAltitude, release = aims[0]-h*(bombLead(aims[0],from:alt)-Self.rampOffset)
            let bomber = FireBomber(x:Self.entry(h,toward:release,lead:Self.planeRun),y:alt,aims:aims,heading:h)
            bombers.append(bomber); bombed = false
            onSound?(SoundEvent(cue:.plane,x:Self.onMap(bomber.x)))
            status = "FIREBOMB RUN INBOUND · -\(offer.cost) CR · C-130 APPROACHING FROM THE \(h > 0 ? "WEST" : "EAST")"
        case .drone:
            launchDrone(toward:x)
            status = "DRONE INBOUND · -\(offer.cost) CR · FLYING IN FROM THE \(drone!.heading > 0 ? "WEST" : "EAST")"
        }
        onSound?(SoundEvent(cue:.order,x:x))
        return true
    }
    /// Advances the support cooldown, supply planes, crates, and strafing jets by one step.
    func updateSupport(_ dt: Double) {
        gunRunCooldown = max(0,gunRunCooldown-dt)
        firebombCooldown = max(0,firebombCooldown-dt)
        skylineClock -= dt
        if skylineClock <= 0 { skylineClock = Self.skylineInterval; refreshSkyline() }
        updateJets(dt)
        for p in planes.indices {
            let h = planes[p].heading
            planes[p].x += h*Self.planeSpeed*dt
            planes[p].y = towardCruise(planes[p].y,dt)
            let ramp = planes[p].x-h*Self.rampOffset
            if !planes[p].dropped && (ramp-planes[p].dropX)*h >= -Self.releaseLead {
                planes[p].dropped = true
                crates.append(SupplyCrate(position:Vec(x:ramp,y:planes[p].y+16),drift:h*Self.planeSpeed))
                status = "SUPPLY CRATE AWAY · PARACHUTE DEPLOYED"
            }
        }
        planes.removeAll { $0.dropped && Self.departed($0.x,heading:$0.heading) }
        for c in crates.indices {
            if !crates[c].landed {
                crates[c].position.x = max(0,min(Self.width,crates[c].position.x+crates[c].drift*dt))
                crates[c].drift *= exp(-Self.crateDrag*dt)
            }
            // Falls whenever nothing holds it up, including after its perch is blasted away.
            let floor = ground(at:crates[c].position.x)
            if crates[c].position.y < floor {
                crates[c].position.y = min(floor,crates[c].position.y+Self.crateFallSpeed*dt)
                if crates[c].position.y >= floor && !crates[c].landed {
                    crates[c].landed = true
                    onSound?(SoundEvent(cue:.deploy,x:crates[c].position.x))
                    status = "SUPPLY CRATE DOWN · TROOPS WITHIN RANGE REARM AUTOMATICALLY"
                }
            } else { crates[c].position.y = floor }
            guard crates[c].landed else { continue }
            crates[c].life -= dt
            let centre = Vec(x:crates[c].position.x,y:crates[c].position.y-6)
            var rearmed = 0
            for i in soldiers.indices where soldiers[i].ammo < soldiers[i].kind.magazine && crates[c].stock > 0 {
                let s = soldiers[i]
                guard hypot(s.position.x-centre.x,s.position.y-Soldier.height/2-centre.y) <= Self.crateRadius else { continue }
                let given = min(crates[c].stock,s.kind.magazine-s.ammo)
                crates[c].stock -= given
                // Troops firing beside the crate are topped up quietly; only real refills are announced.
                if s.ammo*2 < s.kind.magazine { soldiers[i].rearmed = 1.6; rearmed += 1 }
                soldiers[i].ammo += given
            }
            if rearmed > 0 {
                onSound?(SoundEvent(cue:.select,x:centre.x))
                status = crates[c].stock > 0 ? "REARMED \(rearmed) SOLDIER\(rearmed == 1 ? "" : "S") FROM SUPPLY CRATE"
                    : "REARMED \(rearmed) SOLDIER\(rearmed == 1 ? "" : "S") · SUPPLY CRATE EMPTY"
            }
        }
        crates.removeAll { $0.life <= 0 || $0.stock <= 0 }
    }
    /// A transport's height `y` eased toward the current cruising height.
    func towardCruise(_ y: Double,_ dt: Double) -> Double {
        y+max(-Self.climbRate*dt,min(Self.climbRate*dt,transportAltitude-y))
    }
    /// Flies each strafing jet along its pass and fires the rounds due so far. Rounds are
    /// aimed at points walked evenly through the strip and fly as ordinary shots, so a
    /// building in the line of fire takes the hits meant for the ground behind it.
    func updateJets(_ dt: Double) {
        let window = Self.fireWindow
        for j in jets.indices {
            let h = jets[j].heading
            jets[j].x += h*Self.jetSpeed*dt
            jets[j].flash = max(0,jets[j].flash-dt)
            let progress = min(1,max(0,(jets[j].dx-window.lowerBound)/(window.upperBound-window.lowerBound)))
            let due = jets[j].dx >= window.lowerBound ? min(Self.gunRounds,Int(progress*Double(Self.gunRounds-1))+1) : 0
            while jets[j].fired < due {
                let k = Double(jets[j].fired)/Double(Self.gunRounds-1)
                let gun = Self.gunPosition(jets[j])
                let ax = jets[j].targetX+h*(k-0.5)*Self.strafeLength+(random-0.5)*14
                // Aim at the rooftops in the strip, but look past masts and chimneys too thin
                // to catch a round, so near misses don't sail on across the map.
                let aim = Vec(x:ax,y:[-6.0,0,6].map{ground(at:ax+$0)}.max()!+2)
                if jets[j].fired == 0 {
                    onSound?(SoundEvent(cue:.gun,x:gun.x))
                    status = "GUN RUN · ROUNDS ON TARGET"
                }
                // A jet strafing near the map edge may fire while still beyond it; its rounds
                // join the map where their flight crosses the edge.
                var start = gun, v = Self.launch(from:gun,to:aim,speed:Self.gunMuzzleSpeed)
                let edge = Self.onMap(gun.x)
                if edge != gun.x && v.x != 0 {
                    let t = max(0,(edge-gun.x)/v.x)
                    start = Vec(x:edge,y:gun.y+v.y*t+Self.gravity*t*t/2); v.y += Self.gravity*t
                }
                let fuse = jets[j].targetX+h*(Self.strafeLength/2+Self.gunFuseReach)
                shots.append(Shot(position:start,previous:start,velocity:v,radius:Self.gunBlastRadius,fuse:fuse))
                particles.append(Particle(position:gun,velocity:Vec(x:h*Self.jetSpeed*0.3+(random-0.5)*40,y:(random-0.5)*30),life:1+random,total:2,kind:9,size:6+random*6))
                jets[j].fired += 1; jets[j].flash = 0.06; rounds += 1
            }
        }
        jets.removeAll { $0.dx > Self.climbEnd && Self.departed($0.x,heading:$0.heading) }
    }
}
