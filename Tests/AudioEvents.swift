import Foundation
@main struct AudioEvents {
    static func main() {
        var events: [SoundCue] = []
        let w=World(); w.onSound = {events.append($0.cue)}
        func check(_ value:Bool,_ name:String) { if !value { print("FAIL: \(name)"); exit(1) }; print("PASS: \(name)") }
        w.spawn(1); w.attack(Vec(x:905,y:442)); 
        for _ in 0..<60 { w.update(1.0/60) }
        check(events.contains(.deploy) && events.contains(.order) && events.contains(.shot),"deployment, order, and gunfire audio events")
        w.explode(at:Vec(x:928,y:442))
        check(events.contains(.explosion) && events.contains(.glass),"explosion and material-specific glass audio")
        w.cease(); w.move(400)
        for _ in 0..<60 { w.update(1.0/60) }
        check(events.contains(.cease) && events.contains(.step),"cease fire and movement audio")
        w.unit=World.scale; w.fill(108,48,44,7,0); w.unit=1; w.structureDirty=true
        for _ in 0..<300 { w.update(1.0/60) }
        check(events.contains(.collapse) && events.contains(.rubble),"collapse and impact audio events")
        w.reset(); check(events.last == .reset,"reset audio event")
        let baseline=World(); let withAudio=World(); withAudio.onSound={_ in}
        baseline.spawn(4); withAudio.spawn(4)
        baseline.attack(Vec(x:900,y:440)); withAudio.attack(Vec(x:900,y:440))
        for _ in 0..<600 { baseline.update(1.0/60); withAudio.update(1.0/60) }
        check(baseline.voxels == withAudio.voxels && baseline.rounds == withAudio.rounds && baseline.seed == withAudio.seed,"audio routing does not change simulation randomness")
    }
}
