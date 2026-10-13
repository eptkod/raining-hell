import Foundation
@main struct PhysicsTests {
    static func main() {
        func check(_ condition: Bool,_ name: String) { if !condition { print("FAIL: \(name)"); exit(1) }; print("PASS: \(name)") }
        // Scenarios are written in design units; each spans S×S voxels.
        let S=World.scale
        let pristine=World()
        for _ in 0..<600 { pristine.update(1.0/60) }
        print("Intact map detached blocks: \(pristine.collapsed)")
        check(pristine.material(110*S,34*S) == 3 && pristine.material(130*S,34*S) == 3 && pristine.material(150*S,34*S) == 3,"intact roof remains supported")
        check(pristine.collapsed == 0,"intact map remains stable")
        let w=World(); w.unit=S
        // Sever the supporting walls and central column below the first floor.
        w.fill(108,48,44,7,0)
        w.structureDirty=true
        for _ in 0..<15 { w.update(1.0/60) }
        check(!w.chunks.isEmpty,"severed floors detach into falling sections")
        check(w.chunks.count == 1 && w.chunks[0].cells.allSatisfy{ $0.gx >= 0 && $0.material != 10 },"a severed building falls in one piece and keeps its materials until it lands")
        let startY=w.chunks[0].position.y
        w.update(1.0/60)
        check(w.chunks[0].position.y > startY,"detached masonry accelerates downward")
        check(w.material(130*S,34*S) == 0,"unsupported roof leaves static grid")
        check(w.backdrops[w.index(130*S,40*S)] == -1,"rear wall disappears with its supporting floor")
        check((36...54).allSatisfy{ y in (108...151).allSatisfy{ w.backdrops[w.index($0*S,y*S)] == -1 } },"surviving foundation does not preserve a floating backdrop")
        let drop=World(); drop.unit=S
        drop.fill(108,48,44,7,0); drop.structureDirty=true
        var whole=0, afterImpact=0
        for _ in 0..<300 where afterImpact == 0 {
            drop.update(1.0/60)
            let left=drop.chunks.map{$0.cells.count}.reduce(0,+)
            if left > whole { whole=left } else if left < whole { afterImpact=left }
        }
        check(afterImpact > whole/2,"only the part of a building near the impact crumbles; the rest keeps falling")
        let count=w.chunks.count
        let position=w.chunks[0].position.y
        w.paused=true; w.update(1)
        check(w.chunks.count == count && w.chunks[0].position.y == position,"pause freezes collapse")
        w.paused=false
        for _ in 0..<900 { w.update(1.0/60) }
        check(w.chunks.isEmpty,"fallen sections settle")
        check(w.voxels.contains(10),"impacts leave persistent collidable rubble")
        w.reset()
        check(w.chunks.isEmpty && w.collapsed == 0 && w.backdrops.contains(where:{$0 >= 0}),"reset restores structure and backdrops")
        let beam=World(); beam.unit=S
        beam.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        beam.fill(0,80,World.columns/S,World.rows/S-80,2)
        // A one-voxel column: the whole slab bears on a single load line.
        beam.unit=1; beam.fill(80*S,50*S,1,30*S,3); beam.unit=S
        beam.fill(65,43,31,7,3)
        beam.solveStructure()
        check(beam.material(80*S,79*S) == 0 || !beam.chunks.isEmpty,"single overloaded column fails under a heavy slab")
        let ledge=World(); ledge.unit=S
        ledge.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        ledge.fill(0,70,60,World.rows/S-70,1)
        ledge.fill(60,70,3,4,1)
        ledge.fill(100,70,80,World.rows/S-70,1)
        ledge.fill(70,60,30,10,1)
        ledge.fill(100,60,1,10,1)
        ledge.solveStructure()
        check(ledge.material(62*S,70*S) == 1,"short soil overhang holds")
        check(ledge.material(75*S,62*S) == 0 && !ledge.chunks.isEmpty,"undercut soil slab falls")
        check(ledge.material(98*S,62*S) == 1,"slab edge within reach of its column holds")
        let pile=World(); pile.unit=S
        pile.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        pile.fill(0,80,180,World.rows/S-80,2)
        pile.fill(40,70,20,10,3)
        pile.fill(40,50,6,4,1)
        pile.fill(50,50,4,3,2)
        pile.structureDirty=true
        for _ in 0..<900 { pile.update(1.0/60) }
        check(pile.chunks.isEmpty && pile.collapsed > 0,"fallen terrain settles on a building")
        check(!pile.voxels.contains(10),"fallen soil and rock do not turn to rubble")
        check(pile.voxels.filter{$0 == 1}.count == 24*S*S && pile.voxels.filter{$0 == 2}.count == ((World.rows/S-80)*180+12)*S*S,"fallen terrain keeps its material")
        let stack=World(); stack.unit=S
        stack.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        stack.fill(0,80,40,World.rows/S-80,2)
        stack.fill(30,60,10,20,3)
        stack.fill(40,60,12,2,3)
        stack.fill(48,50,3,10,3)
        stack.fill(48,48,14,2,3)
        stack.solveStructure()
        check(stack.material(45*S,60*S) == 3,"floor within reach of its column holds")
        check(stack.material(60*S,48*S) == 0 && stack.material(49*S,55*S) == 3,"overhang stacked on an overhang falls")
        let perch=World(); perch.unit=S
        perch.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        perch.fill(0,70,60,World.rows/S-70,1)
        perch.fill(100,70,80,World.rows/S-70,1)
        perch.fill(52,66,40,4,3)
        perch.fill(70,56,20,10,3)
        perch.solveStructure()
        check(perch.material(80*S,60*S) == 0 && perch.material(56*S,67*S) == 3,"building over a crater falls beyond its reach")
        // Debris rests on a window pane; too much of it snaps the pane and both halves
        // swing down from their frames before falling.
        func pane(_ rubble: Int) -> World {
            let g=World(); g.unit=S
            g.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
            g.fill(0,80,180,World.rows/S-80,2)
            g.fill(40,60,2,20,3); g.fill(54,60,2,20,3)
            g.fill(42,60,12,2,4); g.fill(45,60-rubble,6,rubble,10)
            return g
        }
        let rest=pane(3)
        for _ in 0..<300 { rest.update(1.0/60) }
        check(rest.collapsed == 0 && rest.chunks.isEmpty && rest.material(47*S,58*S) == 10,"light debris rests on glass instead of falling forever")
        let snap=pane(12)
        for _ in 0..<15 { snap.update(1.0/60) }
        check(snap.chunks.count == 2 && snap.chunks.allSatisfy{ $0.hinge != nil },"an overloaded pane tears in two and each half hangs from its frame")
        for _ in 0..<15 { snap.update(1.0/60) }
        check(snap.chunks.count == 2 && snap.chunks[0].angle > 0.1 && snap.chunks[1].angle < -0.1,"torn halves swing down toward the break")
        for _ in 0..<600 { snap.update(1.0/60) }
        check(snap.chunks.isEmpty && !snap.voxels.contains(4) && snap.material(40*S,60*S) == 3 && snap.material(55*S,60*S) == 3,"the broken pane falls clear and its frame survives")
        let blast=World()
        blast.explode(at:Vec(x:1044,y:516),radius:30)
        check(blast.backdrops[blast.index(130*S,51*S)] == -1,"explosions remove rear panels directly")
        let stress=World(); stress.spawn(32); stress.attack(Vec(x:990,y:518))
        for i in 0..<1800 {
            if i%300 == 0 { stress.attack(Vec(x:870+Double(i/300)*55,y:520)) }
            stress.update(1.0/60)
        }
        check(stress.collapsed > 0 && stress.destroyed > 0,"sustained bombardment destroys and collapses the bunker")
        check(stress.score > 0,"bombardment earns mission points")
        // Mission scoring: buildings outscore ground, HVTs outscore buildings.
        let dirt=World(), house=World(), bridge=World()
        dirt.explode(at:Vec(x:1600,y:dirt.ground(at:1600)+2),radius:29)
        house.explode(at:Vec(x:2652,y:464),radius:29)
        bridge.explode(at:Vec(x:2164,y:568),radius:29)
        print("Blast scores · ground \(dirt.score), building \(house.score), bridge \(bridge.score)")
        check(dirt.score > 0 && house.score > dirt.score*5,"destroying buildings scores far more than ground")
        check(bridge.score/bridge.destroyed > house.score/house.destroyed*2,"high-value targets pay a premium per block")
        check(World.points(3) >= World.points(1)*10,"structural blocks are worth at least ten times terrain")
        let demo=World(); demo.unit=S
        check(!demo.extract() && !demo.paused,"extraction is denied below the point requirement")
        let hvt=demo.objectives.firstIndex{$0.name == "KESSEL BRIDGE"}!
        demo.fill(240,57,94,38,0); demo.unit=1
        for _ in 0..<20 { demo.update(1.0/60) }
        check(demo.objectives[hvt].destroyed && demo.score >= demo.objectives[hvt].bonus,"destroying an HVT awards its bonus")
        check(demo.objectives.filter{$0.destroyed}.count == 1,"other objectives stay intact")
        demo.score=World.requirement
        check(demo.extract() && demo.extracted && demo.paused,"extraction completes once the requirement is met")
        demo.reset()
        check(demo.score == 0 && !demo.extracted && demo.objectives.allSatisfy{!$0.destroyed},"reset restores the mission")
        // Troops scramble over rubble and route around obstacles instead of freezing.
        let walk=World(); walk.unit=1
        let gy=walk.troopGround(at:590)
        let wc=Int(600/World.cell), wr=Int((gy-World.top)/World.cell)
        for c in wc..<wc+3 { for r in wr-3..<wr { walk.voxels[walk.index(c,r)]=10 } }
        walk.soldiers=[Soldier(id:1,position:Vec(x:560,y:walk.troopGround(at:560)))]
        walk.soldiers[0].selected=true
        walk.move(680)
        for _ in 0..<900 { walk.update(1.0/60) }
        check(walk.soldiers[0].position.x > 670,"soldier climbs over a three-cell rubble pile")
        for c in wc+30..<wc+33 { for r in wr-30..<wr { walk.voxels[walk.index(c,r)]=3 } }
        walk.move(820)
        for _ in 0..<900 { walk.update(1.0/60) }
        check(walk.soldiers[0].position.x > 800,"soldier does not collide with building walls")
        // The bridge is its own material: troops walk up the ramp and cross on top of the deck.
        let span=World()
        check(span.material(270*S,World.bridgeDeck*S) == 12 && span.material(281*S,80*S) == 12,"bridge deck and piers use bridge material")
        check(span.footings[span.index(281*S,(World.riverBed+1)*S)] && span.material(278*S,(World.riverBed+1)*S) == 12,"bridge piers stand on reinforced footings sunk into rock")
        let deckY=Double(World.bridgeDeck*S)*World.cell+World.top
        span.soldiers=[Soldier(id:1,position:Vec(x:1900,y:span.troopGround(at:1900)))]
        span.move(2720)
        var lowest=0.0
        for _ in 0..<1500 {
            span.update(1.0/60)
            let p=span.soldiers[0].position
            if p.x > 2096 && p.x < 2544 { lowest=max(lowest,p.y) }
        }
        check(span.soldiers[0].position.x > 2700,"soldier crosses the bridge")
        check(lowest > 0 && lowest <= deckY+0.5,"soldier walks over the deck, not through it")
        span.reset(); for _ in 0..<600 { span.update(1.0/60) }
        check(span.collapsed == 0 && span.material(270*S,World.bridgeDeck*S) == 12,"bridge stands on its own")
        // Blowing a gap through the deck takes the bridge out and drops the whole span into
        // the river; troops then ford it and climb the banks both ways.
        let ford=World(), kessel=ford.objectives.firstIndex{$0.name == "KESSEL BRIDGE"}!
        ford.spawn(1,kind:.grenadier,at:1700)
        ford.attack(Vec(x:2200,y:deckY+2))
        for _ in 0..<1800 where !ford.objectives[kessel].destroyed { ford.update(1.0/60) }
        check(ford.objectives[kessel].destroyed,"a lone grenadier can blow the bridge within thirty seconds")
        ford.cease(); for _ in 0..<900 { ford.update(1.0/60) }
        check(!(World.bridgeDeck*S..<World.riverBed*S).contains { y in (262*S..<318*S).contains { ford.material($0,y) == 12 } },"the cut span and its piers fall into the river")
        ford.soldiers=[Soldier(id:9,position:Vec(x:1900,y:ford.troopGround(at:1900)))]
        ford.move(2720)
        for _ in 0..<3000 { ford.update(1.0/60) }
        check(ford.soldiers[0].position.x > 2700,"troops ford the river once the bridge is down")
        ford.move(1900)
        for _ in 0..<3000 { ford.update(1.0/60) }
        check(ford.soldiers[0].position.x < 1910,"troops ford back the other way")
        // Requisition: troops cost credits, a currency separate from the points needed to
        // extract, and land only in the deployment zone.
        let shop=World(), rifle=World.offers[0], grenadier=World.offers[1], squad=World.offers[2]
        check(shop.credits == World.startingCredits && shop.points == 0 && shop.soldiers.isEmpty,"levels start with a credit grant, no points and no troops")
        check(!shop.purchase(rifle,at:World.deployZone.upperBound+200) && shop.spent == 0 && shop.soldiers.isEmpty,"troops cannot be placed outside the deployment zone")
        check(shop.purchase(rifle,at:300) && shop.credits == World.startingCredits-rifle.cost && shop.points == 0 && shop.soldiers.count == 1,"buying a rifleman spends credits, not points")
        check(shop.purchase(squad,at:World.deployZone.lowerBound) && shop.soldiers.count == 5 && shop.soldiers.allSatisfy{World.deployZone.contains($0.position.x)},"squads land inside the zone")
        check(shop.purchase(grenadier,at:500) && shop.soldiers.last?.kind == .grenadier,"grenadiers can be bought")
        check(shop.refusal(grenadier) == "NEED \(grenadier.cost-shop.credits) CR" && !shop.purchase(grenadier,at:500) && shop.credits >= 0,"cannot spend more credits than are available")
        let creditsBefore = shop.credits
        shop.attack(Vec(x:900,y:450))
        for _ in 0..<240 { shop.update(1.0/60) }
        check(shop.score > 0 && shop.points == shop.score && shop.credits == creditsBefore,"troops earn points, never credits mid-round")
        let rich=World(); rich.score = World.requirement; rich.credits = 100_000
        while rich.refusal(rifle) == nil { rich.purchase(rifle,at:300) }
        check(rich.missionReady && rich.points == World.requirement,"spending credits never costs extraction points")
        check(World.credits(for:150_000) == 6_000 && World.credits(for:0) == 0,"a round's points pay 4% of themselves as credits")
        rich.score = 150_000; rich.reset()
        check(rich.credits == World.startingCredits+6_000 && rich.carriedCredits == 6_000 && rich.points == 0,"the next round opens with the grant plus the last round's payout")
        rich.reset()
        check(rich.credits == World.startingCredits && rich.carriedCredits == 0 && rich.bank == 0,"abandoned rounds bank nothing and a pointless round pays nothing")
        // Bank: extraction deposits unspent credits; withdrawing them into a round loses 25%.
        let saver=World(); var saved: [Int] = []; saver.onBankChange = { saved.append($0) }
        saver.purchase(rifle,at:300); saver.score = World.requirement
        check(saver.extract() && saver.bank == World.startingCredits-rifle.cost && saver.banked == saver.bank && saver.credits == 0 && saved == [saver.bank],"extracting banks the unspent credits")
        saver.paused = false; check(saver.extract() && saver.bank == World.startingCredits-rifle.cost,"extracting again does not bank twice")
        saver.reset()
        check(saver.bank == 1_750 && saver.credits == World.startingCredits+6_000,"the bank survives into the next round")
        check(World.delivered(1_000) == 750 && World.delivered(1) == 0,"withdrawals lose 25% in transit")
        check(saver.withdraw(1_000) == 750 && saver.bank == 750 && saver.credits == World.startingCredits+6_000+750 && saver.broughtCredits == 750,"a withdrawal moves 75% of the amount into the round")
        check(saver.withdraw(5_000) == 562 && saver.bank == 0,"withdrawals are capped at the bank balance")
        saver.reset(); check(saver.bank == 0 && saver.broughtCredits == 0 && saver.credits == World.startingCredits,"withdrawn credits are forfeit if the round is abandoned")
        check(World.offers[1].cost > rifle.cost*2 && TroopKind.grenadier.reload > TroopKind.rifleman.reload*2.5 && TroopKind.grenadier.blastRadius > 20,"grenadiers hit harder, reload slower and cost more")
        // Screen shake only follows explosions and collapses the camera can see.
        let blind=World(); blind.visibility = { _,_ in 0 }
        blind.explode(at:Vec(x:900,y:450))
        check(blind.shake == 0,"off-screen explosions do not shake the camera")
        blind.visibility = { p,_ in p.x > 800 && p.x < 1000 ? 1 : 0 }
        blind.explode(at:Vec(x:900,y:450))
        check(blind.shake > 0,"visible explosions shake the camera")
        let full=World(), edge=World(); edge.visibility = { _,_ in 0.15 }
        full.explode(at:Vec(x:900,y:450)); edge.explode(at:Vec(x:900,y:450))
        check(edge.shake > 0 && edge.shake < full.shake*0.1,"destruction barely in frame only lightly shakes the camera")
        let tumble=World(); tumble.unit=S; tumble.visibility = { _,_ in 0 }
        tumble.fill(108,48,44,7,0); tumble.structureDirty=true
        for _ in 0..<15 { tumble.update(1.0/60) }
        check(!tumble.chunks.isEmpty && tumble.shake == 0,"unseen collapses do not shake the camera")
        tumble.visibility = nil
        let seen=World(); seen.unit=S
        seen.fill(108,48,44,7,0); seen.structureDirty=true
        for _ in 0..<15 { seen.update(1.0/60) }
        check(!seen.chunks.isEmpty && seen.shake > 0,"a building tumbling in view shakes the camera")
        // Trajectory lines predict where each attacking soldier's next round lands.
        let aim=World(); aim.spawn(1,at:200)
        check(aim.trajectory(of:aim.soldiers[0]) == nil,"idle soldiers show no trajectory")
        let mark=Vec(x:380,y:aim.ground(at:380))
        aim.attack(mark)
        let arc=aim.trajectory(of:aim.soldiers[0]) ?? []
        check(arc.count > 2 && hypot(arc.last!.x-mark.x,arc.last!.y-mark.y) < World.cell*2,"a predicted trajectory ends at the attack target")
        // Ammo: soldiers carry a finite load, stop firing when empty, and supply crates rearm them.
        let dry=World(); dry.spawn(1,at:300); dry.soldiers[0].ammo = 2
        dry.attack(Vec(x:900,y:450))
        for _ in 0..<600 { dry.update(1.0/60) }
        check(dry.rounds == 2 && dry.soldiers[0].outOfAmmo && dry.soldiers[0].target != nil,"empty soldiers stop firing but keep their orders")
        check(dry.trajectory(of:dry.soldiers[0]) == nil,"empty soldiers show no trajectory")
        dry.soldiers[0].ammo = 10
        check(dry.soldiers[0].lowAmmo && !World.offers.isEmpty,"a quarter load counts as low ammo")
        dry.soldiers[0].ammo = 0
        let crate=World.support[0]
        check(crate.cost == 150 && dry.purchase(crate,at:320) && dry.spent == crate.cost && dry.planes.count == 1 && dry.crates.isEmpty,"a supply crate costs 150 credits and is flown in")
        check(dry.refusal(crate) == nil,"supply crates have no cooldown")
        let skyline = stride(from:0.0,to:World.width,by:World.cell).map{ dry.ground(at:$0) }.min()!
        check(World.planeAltitude+24 < skyline,"transports fly above the tallest structure, gear and ramp included")
        check(dry.planes[0].x <= -World.edgeMargin && dry.planes[0].heading == 1,"a drop on the west half is flown in from beyond the west edge")
        while dry.crates.isEmpty { dry.update(1.0/60) }
        check(dry.crates[0].position.y < World.planeAltitude+30 && !dry.crates[0].landed,"the crate falls out of the plane overhead")
        for _ in 0..<420 { dry.update(1.0/60) }
        check(dry.crates[0].landed && abs(dry.crates[0].position.x-320) < 24,"the drifting crate lands on the chosen spot")
        check(dry.planes.count == 1 && dry.planes[0].x > 320,"the plane flies on past the drop")
        for _ in 0..<900 where !dry.planes.isEmpty { dry.update(1.0/60) }
        check(dry.planes.isEmpty,"the plane flies off the far side of the map after dropping")
        check(dry.crates[0].landed && dry.soldiers[0].ammo > dry.soldiers[0].kind.magazine-4,"a landed crate rearms soldiers in range")
        let far=World(); far.spawn(1,at:200); far.soldiers[0].ammo = 0
        far.purchase(crate,at:200+World.crateRadius*3)
        for _ in 0..<420 { far.update(1.0/60) }
        check(far.soldiers[0].outOfAmmo,"crates do not rearm soldiers out of range")
        for _ in 0..<Int(World.crateLife*60)+60 { far.update(1.0/60) }
        check(far.crates.isEmpty,"crates expire")
        check(far.refusal(crate) == nil,"a supply crate can be called again")
        // A drop on the east half comes in from the east edge, flying west, and still lands on its spot.
        let east=World(), eastX=World.width-1500
        east.purchase(crate,at:eastX)
        check(east.planes[0].x >= World.width+World.edgeMargin && east.planes[0].heading == -1,"a drop on the east half is flown in from beyond the east edge")
        let farDrop=World(); farDrop.purchase(crate,at:World.width/2+100)
        check(farDrop.planes[0].x >= World.width+World.edgeMargin,"a mid-map drop is flown in all the way from the nearer edge")
        while east.crates.isEmpty { east.update(1.0/60) }
        check(east.crates[0].position.x > eastX && east.crates[0].drift < 0,"a westbound plane releases short of the drop, east of it, and the crate drifts west")
        for _ in 0..<420 { east.update(1.0/60) }
        check(east.crates[0].landed && abs(east.crates[0].position.x-eastX) < 24,"a crate from a westbound plane lands on the chosen spot")
        // A crate holds ten rifleman loads; the eleventh empty rifleman gets nothing and the crate is used up.
        let eleven=World(); eleven.spawn(11,at:300)
        for i in eleven.soldiers.indices { eleven.soldiers[i].ammo = 0 }
        eleven.purchase(crate,at:300)
        for _ in 0..<900 { eleven.update(1.0/60) }
        check(World.crateStock == 10*TroopKind.rifleman.magazine,"a crate carries ten rifleman loads")
        check(eleven.soldiers.filter{$0.ammo == $0.kind.magazine}.count == 10 && eleven.soldiers.filter{$0.outOfAmmo}.count == 1,"an empty crate rearms no more troops")
        check(eleven.crates.isEmpty,"a crate is gone once its ammo runs out")
        check(TroopKind.grenadier.magazine < TroopKind.rifleman.magazine,"grenadiers carry fewer rounds")
        // Rifle rounds only chip buildings; riflemen make up for it by moving faster.
        var chips: [Int] = []
        for t in 0..<20 {
            let range=World(); range.spawn(1,at:600); range.attack(Vec(x:880+Double(t*15),y:400))
            var last=range.destroyed
            for _ in 0..<600 where chips.count < (t+1)*3 {
                range.update(1.0/60)
                if range.shots.isEmpty && range.destroyed != last { chips.append(range.destroyed-last); last=range.destroyed }
            }
        }
        check(chips.count == 60 && chips.allSatisfy{ (1...3).contains($0) },"each rifle round destroys one to three voxels")
        var scatter: [Int] = []
        for t in 0..<40 {
            let pile=World(); pile.unit=S
            let gx=60, gy=Int((pile.ground(at:Double(gx*8))-World.top)/8)
            pile.fill(gx,gy-6,20,6,10)
            pile.spawn(1,at:250)
            let x=Double(gx*8)+10+Double(t*3)
            pile.attack(Vec(x:x,y:pile.ground(at:x)))
            for _ in 0..<600 where pile.destroyed == 0 || !pile.shots.isEmpty { pile.update(1.0/60) }
            scatter.append(pile.destroyed)
        }
        check(scatter.allSatisfy{ (3...6).contains($0) },"a rifle round scatters three to six voxels of rubble")
        check(TroopKind.rifleman.walkSpeed >= TroopKind.grenadier.walkSpeed*1.8,"riflemen move much faster than grenadiers")
        let runner=World(); runner.spawn(1,at:300); runner.spawn(1,kind:.grenadier,at:300)
        runner.move(700)
        for _ in 0..<120 { runner.update(1.0/60) }
        check(runner.soldiers[0].position.x-300 > (runner.soldiers[1].position.x-300)*1.6,"a rifleman covers ground faster than a grenadier")
        // Troops hold a line formation instead of piling onto one spot.
        func gaps(_ w: World) -> [Double] { let xs=w.soldiers.map{$0.position.x}.sorted(); return zip(xs,xs.dropFirst()).map{$1-$0} }
        let line=World(); line.spawn(4,at:300); line.move(560)
        for _ in 0..<600 { line.update(1.0/60) }
        check(gaps(line).allSatisfy{ $0 > World.formationSpacing-1 },"a move order spreads the squad into a line at the rally point")
        let pileup=World(); for _ in 0..<5 { pileup.spawn(1,at:400) }
        for _ in 0..<600 { pileup.update(1.0/60) }
        check(gaps(pileup).allSatisfy{ $0 > World.formationSpacing-1 },"idle troops spawned on one spot edge apart into a line")
        let quick=World(); quick.purchase(crate,at:600)
        check(quick.refusal(crate) == nil && quick.purchase(crate,at:700) && quick.planes.count == 2,"a second crate can be called immediately")
        dry.purchase(crate,at:400)
        dry.reset(); check(dry.crates.isEmpty && dry.planes.isEmpty && dry.gunRunCooldown == 0,"reset clears supply drops and the cooldown")
        // Gun run: a 1,000-credit strafing pass that walks a cannon burst across the clicked strip.
        let gunRun=World.support[1]
        check(gunRun.kind == .gunRun && gunRun.cost == 1000,"a gun run costs 1,000 credits")
        for target in [1700.0,3400.0,5300.0] {
            let strafe=World()
            var impacts: [Double] = []
            strafe.onSound = { if $0.cue == .explosion, let x = $0.x { impacts.append(x) } }
            check(strafe.purchase(gunRun,at:target) && strafe.credits == World.startingCredits-gunRun.cost && strafe.jets.count == 1,"a gun run is flown in at \(Int(target))")
            let jet0 = strafe.jets[0]
            check(jet0.heading == World.heading(toward:target) && (jet0.x <= -World.edgeMargin || jet0.x >= World.width+World.edgeMargin),"the jet enters from beyond the nearer map edge (\(Int(target)))")
            check(strafe.refusal(World.support[0]) == nil && strafe.refusal(gunRun) != nil,"a gun run locks only the gun run")
            var lowest = -Double.infinity, clipped = false; let strip = strafe.ground(at:target)
            for _ in 0..<600 where !strafe.jets.isEmpty {
                strafe.update(1.0/60)
                if let jet = strafe.jets.first {
                    let y = World.strafePath(jet.dx,low:jet.low).y
                    lowest = max(lowest,y)
                    if y+20 >= strafe.ground(at:jet.x) { clipped = true }
                }
            }
            check(lowest > World.jetAltitude+30 && lowest < strip-40,"the jet dives but pulls out well above the strip (\(Int(target)): lowest \(Int(lowest)), ground \(Int(strip)))")
            check(!clipped,"the jet never flies through a structure on its pass (\(Int(target)))")
            for _ in 0..<120 { strafe.update(1.0/60) }
            check(strafe.jets.isEmpty && strafe.rounds == World.gunRounds,"the jet fires its whole burst and leaves (\(Int(target)))")
            let hits = impacts.filter { abs($0-target) <= World.strafeLength/2+20 }
            print("Gun run at \(Int(target)): \(impacts.count) impacts, \(hits.count) in the strip, \(strafe.destroyed) blocks, \(strafe.score) pts")
            // Targets on the east half are strafed by a jet coming in from the east, flying west.
            let east = target > World.width/2
            let ahead = east ? target-impacts.min()! : impacts.max()!-target, behind = east ? impacts.max()!-target : target-impacts.min()!
            check(strafe.destroyed > 0 && ahead <= World.strafeLength/2+20 && behind <= -World.fireWindow.lowerBound,"no round overshoots the strip or lands behind the jet (\(Int(target)))")
            if target != 1700 {
                // In the town and the fortress, walls between the jet and the strip take part of the burst.
                check(hits.count >= World.gunRounds/3,"a third or more of the burst still reaches the strip past cover (\(Int(target)))")
            } else {
                check(hits.count >= World.gunRounds*7/8,"the burst lands in the strip (\(Int(target)))")
                check(impacts.min()! < target && impacts.max()! > target && impacts.max()!-impacts.min()! > World.strafeLength/2,"the burst is walked across the strip (\(Int(target)): \(Int(impacts.min()!))-\(Int(impacts.max()!)))")
            }
        }
        // A gun run locks itself for 45 s; crates stay free throughout.
        let repeatRun=World(); repeatRun.credits = 5_000; repeatRun.purchase(gunRun,at:2000)
        for _ in 0..<Int(World.gunRunCooldown*60)-30 { repeatRun.update(1.0/60) }
        check(repeatRun.refusal(World.support[0]) == nil && repeatRun.refusal(gunRun) != nil,"a gun run stays locked for its 45 seconds")
        for _ in 0..<60 { repeatRun.update(1.0/60) }
        check(World.gunRunCooldown == 45 && repeatRun.refusal(gunRun) == nil,"a gun run is available again after 45 seconds")
        let cleared=World(); cleared.purchase(gunRun,at:2000)
        cleared.reset(); check(cleared.jets.isEmpty,"reset clears strafing jets")
        // Firebombs: a 2,000-credit C-130 run whose napalm sets the town burning for minutes.
        let firebomb=World.support[2]
        check(firebomb.kind == .firebomb && firebomb.cost == 2000,"a firebomb run costs 2,000 credits")
        let town=World(), townX=2750.0
        check(town.purchase(firebomb,at:townX) && town.credits == World.startingCredits-2000 && town.bombers.count == 1,"a C-130 firebomber is flown in")
        check(town.refusal(firebomb)?.hasPrefix("COOLDOWN") == true && town.cooldown(.supplyCrate) == 0 && town.cooldown(.gunRun) == 0,"a firebomb run locks only firebombs")
        for _ in 0..<15*60 { town.update(1.0/60) }
        check(town.bombers.allSatisfy{ $0.released == World.firebombCount } && town.fireBombs.isEmpty,"the C-130 drops all \(World.firebombCount) canisters")
        // A firebomb run on the east half comes in from the east and still lays its stick on target.
        let eastFire=World(), eastFireX=World.width-700
        eastFire.purchase(firebomb,at:eastFireX)
        check(eastFire.bombers[0].heading == -1 && eastFire.bombers[0].x >= World.width+World.edgeMargin,"an east-half firebomb run comes in from beyond the east edge")
        for _ in 0..<12*60 { eastFire.update(1.0/60) }
        let eastLit = eastFire.fire.burning.map{ Double($0%World.columns)*World.cell }
        check(eastFire.bombers.allSatisfy{ $0.done } && eastLit.count > 20 && eastLit.filter{ abs($0-eastFireX) < 300 }.count*4 > eastLit.count*3,"a westbound C-130 lands its canisters around the target (\(eastLit.count) cells)")
        let lit = town.fire.burning.map{ Double($0%World.columns)*World.cell }
        check(lit.count > 60 && lit.allSatisfy{ abs($0-townX) < 500 },"the canisters start fires around the target (\(lit.count) cells)")
        check(town.fire.burning.contains{ town.voxels[$0] == 0 && town.backdrops[$0] >= 0 },"canisters break into buildings and set rooms burning")
        let early=town.destroyed, earlyScore=town.score
        for _ in 0..<45*60 { town.update(1.0/60) }
        print("Firebombs at \(Int(townX)): \(early) blocks after 15 s, \(town.destroyed) after 60 s, \(town.score) pts")
        check(town.destroyed > early+60 && town.score > earlyScore,"fire keeps damaging infrastructure long after the bombs land")
        check(town.chunks.count < 3,"fire damage is gradual, not an instant collapse")
        var burnt=60
        while !town.fire.burning.isEmpty && burnt < 600 { for _ in 0..<60 { town.update(1.0/60) }; burnt += 1 }
        check(town.fire.burning.isEmpty,"the fires die out on their own (out after \(burnt) s)")
        check(town.fire.char.contains(3),"burnt-out rooms are left sooty")
        // A single burning room spreads through its contents, then burns out.
        let room=World()
        let start=room.index(130*S,53*S)
        check(room.backdrops[start] >= 0 && room.ignite(start,1),"furnishings in the bunker can be lit")
        for _ in 0..<20*60 { room.update(1.0/60) }
        check(room.fire.burning.count > 40,"fire spreads through a room (\(room.fire.burning.count) cells)")
        room.reset(); check(room.fire.burning.isEmpty && room.bombers.isEmpty && room.firebombCooldown == 0 && !room.fire.char.contains(where:{$0 > 0}),"reset puts out every fire")
        // Non-combustible structure only weakens under heat; glass shatters first.
        let glass=World(), pane=glass.voxels.firstIndex(of:4)!
        glass.heatCell(pane,5)
        check(glass.voxels[pane] == 0,"heat shatters glass")
        let slab=World(), block=slab.index(110*S,34*S)
        slab.heatCell(block,10)
        check(slab.voxels[block] == 3,"a brief flame doesn't destroy concrete")
        let lockout=World(); lockout.credits = 5_000; lockout.purchase(firebomb,at:townX)
        for _ in 0..<Int(World.firebombCooldown*60)-30 { lockout.update(1.0/60) }
        check(lockout.refusal(firebomb) != nil,"firebombs stay locked for their 120 seconds")
        for _ in 0..<60 { lockout.update(1.0/60) }
        check(World.firebombCooldown == 120 && lockout.refusal(firebomb) == nil,"firebombs are available again after 120 seconds")
        // RPG gunner: 1,200 credits, 7 rockets, a 7 s reload, fired by hand at the pointer.
        let rpg=World.offers[3]
        check(rpg.kind == .rpg && rpg.cost == 1200 && rpg.count == 1,"an RPG gunner costs 1,200 credits")
        check(TroopKind.rpg.magazine == 7 && TroopKind.rpg.reload == 7 && TroopKind.rpg.manualAim && !TroopKind.grenadier.manualAim,"an RPG gunner carries 7 rockets and reloads for 7 seconds")
        check(abs(TroopKind.rpg.walkSpeed-TroopKind.grenadier.walkSpeed) <= 6,"an RPG gunner walks about as fast as a grenadier")
        let launcher=World()
        check(launcher.purchase(rpg,at:300) && launcher.soldiers[0].kind == .rpg && launcher.rocketsSelected,"an RPG gunner can be bought and is aimed by hand")
        for _ in 0..<60 { launcher.update(1.0/60) }
        var booms: [Double] = []
        launcher.onSound = { if $0.cue == .explosion, let x = $0.x { booms.append(x) } }
        let rpgAim=Vec(x:900,y:launcher.ground(at:900)-120)
        let predicted=launcher.rocketTrajectory(of:launcher.soldiers[0],at:rpgAim)!
        launcher.attack(rpgAim)
        check(launcher.shots.count == 1 && launcher.shots[0].rocket && launcher.soldiers[0].ammo == 6 && launcher.soldiers[0].target == nil,"a click fires one rocket and sets no attack target")
        launcher.attack(rpgAim)
        check(launcher.shots.count == 1 && launcher.status == "RPG RELOADING","clicking again while reloading fires nothing and says RPG RELOADING")
        for _ in 0..<600 where booms.isEmpty { launcher.update(1.0/60) }
        check(booms.count == 1 && abs(booms[0]-predicted.last!.x) < 8,"the rocket follows its previewed path (impact \(Int(booms.first ?? -1)), predicted \(Int(predicted.last!.x)))")
        check(predicted.last!.y > rpgAim.y+2 || predicted.last!.x < rpgAim.x,"the rocket drops below the line to the pointer")
        let rise=zip(predicted,predicted.dropFirst()).map{$1.y-$0.y}
        check(rise.first! < 0 && rise.last! > rise.first!,"the rocket's path curves downward over time")
        for _ in 0..<Int(TroopKind.rpg.reload*60)+5 { launcher.update(1.0/60) }
        launcher.attack(rpgAim)
        check(launcher.soldiers[0].ammo == 5,"the RPG fires again once its 7 s reload is over")
        let dryTube=World(); dryTube.spawn(1,kind:.rpg,at:300); dryTube.soldiers[0].cooldown=0
        for _ in 0..<7 { dryTube.attack(rpgAim); dryTube.soldiers[0].cooldown=0 }
        dryTube.attack(rpgAim)
        check(dryTube.soldiers[0].outOfAmmo && dryTube.rounds == 7 && dryTube.status.hasPrefix("RPG OUT OF AMMO"),"an RPG gunner fires seven rockets, then is empty")
        // Mixed selections: the RPG holds fire and the others take the attack order.
        let mixed=World(); mixed.spawn(1,at:300); mixed.spawn(1,kind:.rpg,at:330)
        for _ in 0..<60 { mixed.update(1.0/60) }
        check(!mixed.rocketsSelected,"a mixed selection does not aim rockets")
        mixed.attack(rpgAim)
        for _ in 0..<120 { mixed.update(1.0/60) }
        check(mixed.soldiers[0].target != nil && mixed.soldiers[1].target == nil && mixed.soldiers[1].ammo == 7 && !mixed.shots.contains{$0.rocket},"with other troops selected the RPG gunner holds fire")
        let squadRPG=World(); squadRPG.spawn(3,kind:.rpg,at:300)
        for _ in 0..<60 { squadRPG.update(1.0/60) }
        check(squadRPG.rocketsSelected && squadRPG.fireRockets(at:rpgAim) == 3,"several selected RPG gunners all fire on one click")
        // Reloading slows the gunner to half pace.
        let pacing=World(); pacing.spawn(1,kind:.rpg,at:200); pacing.spawn(1,kind:.rpg,at:200)
        for _ in 0..<60 { pacing.update(1.0/60) }
        for i in pacing.soldiers.indices { pacing.soldiers[i].selected = i == 0 }
        pacing.fireRockets(at:Vec(x:200,y:World.top))
        for i in pacing.soldiers.indices { pacing.soldiers[i].selected = true }
        let starts=pacing.soldiers.map{$0.position.x}
        pacing.move(600)
        for _ in 0..<120 { pacing.update(1.0/60) }
        let walked=zip(pacing.soldiers,starts).map{$0.position.x-$1}
        check(pacing.soldiers[0].reloading && walked[1] > walked[0]*1.6 && walked[0] > 10,"a reloading RPG gunner walks at half pace (\(Int(walked[0])) vs \(Int(walked[1])) px)")
        let finalScore = shop.score
        shop.reset()
        check(shop.spent == 0 && shop.points == 0 && shop.credits == World.startingCredits+World.credits(for:finalScore) && shop.soldiers.isEmpty,"reset opens a new round with fresh credits")
        print("All structural physics checks passed. Peak scenario ended with \(stress.chunks.count) moving chunks.")
    }
}
