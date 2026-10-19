import Foundation

/// A kamikaze quadcopter called in from the SUPPORT tab. It flies in from the map edge (the
/// same side rules as the aircraft) to the point it was called on, then the player pilots it:
/// it chases the pointer's world position until it hits something, the player detonates it,
/// or its battery dies and it falls. Flown or dropped into water it shorts out instead: the
/// charge never goes off, and the dead airframe sinks (see `World.shortOutDrone`).
///
/// Flight is a simple quadcopter model: the rotors push along the body's up axis with a
/// capped thrust, the body can only tilt so far and so fast, and gravity and air drag act on
/// it. A velocity controller picks the tilt and thrust that would carry it toward the aim, so
/// it leans into turns, overshoots a little when reversing, and settles into a hover.
struct Drone {
    var position: Vec
    var velocity: Vec
    /// +1 flying east (in from the west edge), -1 flying west (in from the east edge).
    let heading: Double
    /// Where the drone was called on; it flies itself there before handing over control.
    let arrival: Vec
    /// Under the player's control once it has reached `arrival`.
    var piloted = false
    /// The world point it is steering toward while piloted.
    var aim: Vec
    /// Body tilt from upright in radians, positive leaning east. Thrust acts along it.
    var tilt = 0.0
    /// Thrust as a share of `World.droneThrust`, for the rotor blur.
    var throttle = 0.5
    /// Seconds of powered flight left once piloted; at zero the motors cut.
    var battery = World.droneBattery
    var powered: Bool { battery > 0 }
    /// Shorted out in water: dead, unarmed, and only sinking or lying where it came to rest.
    var shorted = false
    /// Seconds a shorted drone has lain still.
    var resting = 0.0
}

extension World {
    static let droneCost = 300
    static let droneCooldownTime = 10.0
    /// Blast of the drone's charge: a touch bigger than an RPG rocket.
    static let droneBlastRadius = 36.0
    /// Seconds of piloted flight on a full battery.
    static let droneBattery = 20.0
    /// Peak rotor thrust (px/s²), a little over twice gravity.
    static let droneThrust = 2.2*gravity
    /// Furthest the body leans from upright, and how fast it can change its lean.
    static let droneMaxTilt = 0.95, droneTiltRate = 6.0
    /// Linear air drag (per second); with the tilt limit this caps level speed near 380 px/s.
    static let droneDrag = 1.6
    /// Fastest the flight controller asks for, and the braking it plans for when arriving.
    static let droneTopSpeed = 380.0, droneBraking = 520.0
    /// How hard the controller corrects a velocity error (per second).
    static let droneGain = 3.2
    /// Transit speed on the way in from the map edge, before the player takes over.
    static let droneTransitSpeed = 900.0
    /// Cruise height on the way in: this far above the tallest standing block.
    static let droneClearance = 140.0
    /// Half the drone's body width and height, for contact with blocks.
    static let droneHalf = Vec(x:7,y:3)

    var droneCruise: Double { max(Self.flightCeiling,skyline-Self.droneClearance) }

    /// Launches a drone toward `x` from the run-in edge.
    func launchDrone(toward x: Double) {
        droneCooldown = Self.droneCooldownTime
        let h = approach(toward:x), y = droneCruise
        let start = Vec(x:Self.entry(h,toward:x,lead:400),y:y)
        drone = Drone(position:start,velocity:Vec(x:h*Self.droneTransitSpeed,y:0),heading:h,arrival:Vec(x:x,y:y),aim:Vec(x:x,y:y))
    }
    /// Points a piloted drone at a world position.
    func steerDrone(toward p: Vec) {
        guard drone?.piloted == true else { return }
        drone?.aim = p
    }
    /// Sets off the drone's charge where it is. Returns false with no drone under control.
    @discardableResult func detonateDrone() -> Bool {
        guard let d = drone, d.piloted || d.position.x >= 0 && d.position.x <= Self.width else { return false }
        drone = nil
        explode(at:d.position,radius:Self.droneBlastRadius)
        status = "DRONE DETONATED"
        return true
    }

    /// Flies the drone one step: the transit leg in from the edge, then piloted flight.
    func updateDrone(_ dt: Double) {
        droneCooldown = max(0,droneCooldown-dt)
        updateWrecks(dt)
        guard var d = drone else { return }
        if !d.piloted {
            // Transit: a fast, steady run in at cruise height, slowing on the approach so the
            // hand-over to the player is at the drone's own top speed.
            let dx = d.arrival.x-d.position.x, distance = abs(dx)
            let speed = min(Self.droneTransitSpeed,max(Self.droneTopSpeed,distance*1.6))
            d.velocity = Vec(x:(dx >= 0 ? 1 : -1)*speed,y:(d.arrival.y-d.position.y)*2)
            d.tilt = (dx >= 0 ? 1 : -1)*Self.droneMaxTilt*0.6*speed/Self.droneTransitSpeed
            d.position = d.position+d.velocity*dt
            if distance <= speed*dt || distance < Self.droneTopSpeed/1.6 {
                d.piloted = true; d.aim = d.position
                status = "DRONE ONLINE · STEER WITH THE POINTER · CLICK OR [\(Keybinds.shared.label(.detonate))] TO DETONATE"
                onSound?(SoundEvent(cue:.select,x:d.position.x))
            }
            drone = d
            return
        }
        let g = Self.gravity, k = Self.droneDrag
        if d.powered {
            d.battery -= dt
            if !d.powered { status = "DRONE BATTERY DEAD · MOTORS CUT" }
        }
        var thrust = 0.0
        if d.powered {
            // Velocity wanted: toward the aim at a speed it can still brake from in time.
            let ex = d.aim.x-d.position.x, ey = d.aim.y-d.position.y, distance = hypot(ex,ey)
            let speed = min(Self.droneTopSpeed,(2*Self.droneBraking*distance).squareRoot())
            let want = distance > 0.5 ? Vec(x:ex/distance*speed,y:ey/distance*speed) : Vec(x:0,y:0)
            // Thrust that would give the corrective acceleration after gravity and drag.
            let tx = (want.x-d.velocity.x)*Self.droneGain+k*d.velocity.x
            let ty = (want.y-d.velocity.y)*Self.droneGain+k*d.velocity.y-g
            // Rotors only push "up" through the body: lean toward the thrust, within limits,
            // then give whatever thrust holds the wanted climb or sink at that lean.
            let lean = max(-Self.droneMaxTilt,min(Self.droneMaxTilt,atan2(tx,max(1,-ty))))
            let turn = Self.droneTiltRate*dt
            d.tilt += max(-turn,min(turn,lean-d.tilt))
            thrust = max(0,min(Self.droneThrust,-ty/cos(d.tilt)))
        }
        d.throttle = thrust/Self.droneThrust
        let ax = thrust*sin(d.tilt)-k*d.velocity.x, ay = g-thrust*cos(d.tilt)-k*d.velocity.y
        d.velocity = Vec(x:d.velocity.x+ax*dt,y:d.velocity.y+ay*dt)
        // Step in short hops so a fast drone can't pass through a thin wall.
        let steps = max(1,Int(hypot(d.velocity.x,d.velocity.y)*dt/2)+1)
        for _ in 0..<steps {
            d.position = d.position+d.velocity*(dt/Double(steps))
            // The map's sides and the top of the open sky hold it in.
            if d.position.x < Self.droneHalf.x { d.position.x = Self.droneHalf.x; d.velocity.x = max(0,d.velocity.x) }
            if d.position.x > Self.width-Self.droneHalf.x { d.position.x = Self.width-Self.droneHalf.x; d.velocity.x = min(0,d.velocity.x) }
            let ceiling = Self.top-Self.skyHeight+20
            if d.position.y < ceiling { d.position.y = ceiling; d.velocity.y = max(0,d.velocity.y) }
            // Water shorts the electronics before the charge can fire.
            if droneInWater(d.position) { shortOutDrone(d); return }
            if droneTouches(d.position) || d.position.y >= Self.bottom {
                drone = nil
                explode(at:d.position,radius:Self.droneBlastRadius)
                status = "DRONE IMPACT"
                return
            }
        }
        drone = d
    }
    /// Whether a drone centred at `p` has gone into water.
    func droneInWater(_ p: Vec) -> Bool {
        waterAt(p) > 0.3 || waterAt(p+Vec(x:0,y:Self.droneHalf.y)) > 0.5
    }
    /// Most dead drones left lying about; the oldest goes when another is added.
    static let maxWrecks = 6
    /// A drone that has hit water: a splash, a fizz of sparks and steam, and no blast. It
    /// leaves the air (so another can be called once the cooldown is over) and sinks as a wreck.
    func shortOutDrone(_ d: Drone) {
        var wreck = d
        wreck.shorted = true; wreck.piloted = false; wreck.battery = 0; wreck.throttle = 0
        wreck.velocity = wreck.velocity*0.35
        drone = nil
        wrecks.append(wreck)
        if wrecks.count > Self.maxWrecks { wrecks.removeFirst(wrecks.count-Self.maxWrecks) }
        ripple(at:d.position,d.velocity)
        for _ in 0..<10 where particles.count < 2800 {
            particles.append(Particle(position:d.position,velocity:Vec(x:(water.random()-0.5)*120,y:-40-water.random()*110),life:0.25+water.random()*0.35,total:0.6,kind:8,size:1+water.random()))
        }
        for _ in 0..<4 where particles.count < 2800 {
            particles.append(Particle(position:d.position,velocity:Vec(x:(water.random()-0.5)*20,y:-25-water.random()*25),life:1.2+water.random(),total:2.2,kind:Self.mistKind,size:5+water.random()*5))
        }
        onSound?(SoundEvent(cue:.cease,x:d.position.x))
        status = "DRONE DOWN IN THE WATER · SHORTED OUT · NO DETONATION"
    }
    /// Dead drones sink slowly through water, fall through air, and come to rest on whatever
    /// is under them. They never explode.
    func updateWrecks(_ dt: Double) {
        guard !wrecks.isEmpty else { return }
        for k in wrecks.indices {
            var w = wrecks[k]
            let wet = droneInWater(w.position)
            // In water it is nearly afloat and heavily dragged, so it settles gently.
            let ay = Self.gravity*(wet ? 0.12 : 1), drag = wet ? 4.5 : Self.droneDrag
            w.velocity = Vec(x:w.velocity.x*exp(-drag*dt),y:(w.velocity.y+ay*dt)*exp(-drag*dt))
            w.tilt += ((w.heading > 0 ? 0.5 : -0.5)-w.tilt)*min(1,dt*(wet ? 0.8 : 2))
            let next = w.position+w.velocity*dt
            if droneTouches(next) || next.y >= Self.bottom-Self.droneHalf.y {
                w.velocity = Vec(x:0,y:0); w.resting += dt
            } else {
                w.position = Vec(x:max(Self.droneHalf.x,min(Self.width-Self.droneHalf.x,next.x)),y:next.y); w.resting = 0
                // A trail of bubbles while it sinks.
                if wet && particles.count < 2600 && water.random() < 6*dt {
                    particles.append(Particle(position:w.position,velocity:Vec(x:(water.random()-0.5)*8,y:-30-water.random()*20),life:0.6+water.random()*0.5,total:1.1,kind:Self.mistKind,size:1.5+water.random()))
                }
            }
            wrecks[k] = w
        }
    }
    /// Whether a drone centred at `p` is touching a block.
    func droneTouches(_ p: Vec) -> Bool {
        let h = Self.droneHalf
        return [Vec(x:0,y:0),Vec(x:-h.x,y:0),Vec(x:h.x,y:0),Vec(x:-h.x,y:h.y),Vec(x:h.x,y:h.y),Vec(x:0,y:h.y)]
            .contains { material(at:p+$0) != 0 }
    }
}
