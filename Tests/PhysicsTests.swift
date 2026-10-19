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
        // The block outweighs the slab end resting on the lip, so the whole slab tips in.
        check(perch.material(80*S,60*S) == 0 && perch.material(56*S,67*S) == 0,"building over a crater falls beyond its reach")
        check(perch.chunks.count == 1 && perch.chunks[0].rooted && perch.chunks[0].hinge.map{ abs($0.x-60*World.cell*Double(S)) < 1 } == true,"a slab overbalanced past the crater lip tips in about the lip")
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
        // An earth bank as tall as the soldier is a step, not an obstacle; a taller one is not.
        let wall=World(); wall.unit=1
        let wy=wall.troopGround(at:590), wwr=Int((wy-World.top)/World.cell)
        for c in wc..<wc+3 { for r in wwr-World.climbCells..<wwr { wall.voxels[wall.index(c,r)]=2 } }
        wall.soldiers=[Soldier(id:1,position:Vec(x:560,y:wall.troopGround(at:560)))]
        wall.soldiers[0].selected=true
        wall.move(680)
        for _ in 0..<900 { wall.update(1.0/60) }
        check(wall.soldiers[0].position.x > 670,"soldier climbs a wall as tall as itself")
        for c in wc..<wc+3 { wall.voxels[wall.index(c,wwr-World.climbCells-1)]=2 }
        check(wall.plan(from:Vec(x:560,y:wall.troopGround(at:560)),to:680).allSatisfy{$0 < wc},"soldier will not plan up a wall taller than itself")
        // A stair of full-height steps is climbable, even though the body test looks two columns ahead.
        let stair=World(); stair.unit=1
        let sy=stair.troopGround(at:590), swr=Int((sy-World.top)/World.cell)
        for k in 0..<6 { for c in wc+k..<wc+12 { for r in swr-World.climbCells*(k+1)..<swr-World.climbCells*k { stair.voxels[stair.index(c,r)]=2 } } }
        stair.soldiers=[Soldier(id:1,position:Vec(x:560,y:stair.troopGround(at:560)))]
        stair.soldiers[0].selected=true
        stair.move(Double(wc+11)*World.cell)
        for _ in 0..<900 { stair.update(1.0/60) }
        check(stair.soldiers[0].position.y < sy-Double(5*World.climbCells)*World.cell,"soldier climbs a steep stair of full-height steps")
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
        let crate=World.support[0], gunRunOffer=World.support[1]
        check(crate.cost == 150 && dry.purchase(crate,at:320) && dry.spent == crate.cost && dry.planes.count == 1 && dry.crates.isEmpty,"a supply crate costs 150 credits and is flown in")
        check(dry.refusal(crate) == nil,"supply crates have no cooldown")
        let skyline = stride(from:0.0,to:World.width,by:World.cell).map{ dry.ground(at:$0) }.min()!
        check(dry.planes[0].y+24 < skyline-200,"transports fly far above the tallest structure, gear and ramp included")
        check(dry.planes[0].x <= -World.edgeMargin && dry.planes[0].heading == 1,"a drop on the west half is flown in from beyond the west edge")
        while dry.crates.isEmpty { dry.update(1.0/60) }
        // Knocking down the tallest structures lowers the skyline, and planes in flight descend to follow it.
        let felled=World(); felled.purchase(crate,at:600)
        let highAlt=felled.transportAltitude, planeY=felled.planes[0].y
        check(abs(planeY-highAlt) < 1 && highAlt+World.flightClearance <= skyline+1,"planes cruise a fixed clearance above the tallest standing block")
        for x in 0..<World.columns {
            for y in 0..<World.rows where Double(y)*World.cell+World.top < 330 { felled.voxels[felled.index(x,y)] = 0 }
        }
        for _ in 0..<120 { felled.update(1.0/60) }
        check(felled.skyline > skyline+150 && felled.transportAltitude > highAlt+150,"the cruising height drops once the tall structures are gone")
        check(felled.planes.isEmpty || felled.planes[0].y > planeY+40,"a plane in flight descends toward the new cruising height")
        check(dry.crates[0].position.y < dry.planes[0].y+30 && !dry.crates[0].landed,"the crate falls out of the plane overhead")
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
        let sided=World(); sided.supportSide = -1; sided.purchase(crate,at:320); sided.purchase(gunRunOffer,at:1700)
        check(sided.planes[0].heading == -1 && sided.planes[0].x >= World.width+World.edgeMargin && sided.jets[0].heading == -1,"a chosen side overrides the nearer edge")
        sided.supportSide = 1; sided.purchase(crate,at:World.width-200)
        check(sided.planes[1].heading == 1 && sided.planes[1].x <= -World.edgeMargin,"support can be flown in from the far edge")
        sided.reset(); check(sided.supportSide == nil,"reset clears the chosen side")
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
                    let y = jet.path.y
                    lowest = max(lowest,y)
                    if y+20 >= strafe.ground(at:jet.x) { clipped = true }
                }
            }
            check(lowest > strafe.jetCruise+30 && lowest < strip-40,"the jet dives but pulls out well above the strip (\(Int(target)): lowest \(Int(lowest)), ground \(Int(strip)))")
            check(!clipped,"the jet never flies through a structure on its pass (\(Int(target)))")
            for _ in 0..<120 { strafe.update(1.0/60) }
            check(strafe.jets.isEmpty && strafe.rounds == World.gunRounds,"the jet fires its whole burst and leaves (\(Int(target)))")
            let hits = impacts.filter { abs($0-target) <= World.strafeLength/2+20 }
            print("Gun run at \(Int(target)): \(impacts.count) impacts, \(hits.count) in the strip, \(strafe.destroyed) blocks, \(strafe.score) pts")
            // Targets on the east half are strafed by a jet coming in from the east, flying west.
            let east = target > World.width/2
            let ahead = east ? target-impacts.min()! : impacts.max()!-target, behind = east ? impacts.max()!-target : target-impacts.min()!
            check(strafe.destroyed > 0 && ahead <= World.strafeLength/2+20 && behind <= -World.fireWindow.lowerBound,"no round overshoots the strip or lands behind the jet (\(Int(target)): ahead \(Int(ahead)), behind \(Int(behind)))")
            if target != 1700 {
                // In the town and the fortress, walls between the jet and the strip take part of the burst.
                check(hits.count >= World.gunRounds/3,"a third or more of the burst still reaches the strip past cover (\(Int(target)))")
            } else {
                check(hits.count >= World.gunRounds*7/8,"the burst lands in the strip (\(Int(target)))")
                check(impacts.min()! < target && impacts.max()! > target && impacts.max()!-impacts.min()! > World.strafeLength/2,"the burst is walked across the strip (\(Int(target)): \(Int(impacts.min()!))-\(Int(impacts.max()!)))")
            }
        }
        // A gun run locks itself for 30 s; crates stay free throughout.
        let repeatRun=World(); repeatRun.credits = 5_000; repeatRun.purchase(gunRun,at:2000)
        for _ in 0..<Int(World.gunRunCooldown*60)-30 { repeatRun.update(1.0/60) }
        check(repeatRun.refusal(World.support[0]) == nil && repeatRun.refusal(gunRun) != nil,"a gun run stays locked for its 30 seconds")
        for _ in 0..<60 { repeatRun.update(1.0/60) }
        check(World.gunRunCooldown == 30 && repeatRun.refusal(gunRun) == nil,"a gun run is available again after 30 seconds")
        let cleared=World(); cleared.purchase(gunRun,at:2000)
        cleared.reset(); check(cleared.jets.isEmpty,"reset clears strafing jets")
        // Dev mode: infinite credits buy anything without spending and bank nothing.
        let dev=World(); dev.reset(); dev.credits=0; dev.devMode=true
        check(dev.refusal(cost:1_000_000) == nil,"dev mode never refuses on cost")
        check(dev.purchase(World.offers[0],at:World.deployZone.lowerBound+20) && dev.credits == 0,"dev mode purchases cost nothing")
        check(dev.purchase(World.support[0],at:1000) && dev.credits == 0,"dev mode support costs nothing")
        check(dev.purchase(World.support[1],at:3000) && dev.purchase(World.support[1],at:3000),"dev mode gun runs have no cooldown")
        check(dev.purchase(World.support[2],at:3000) && dev.purchase(World.support[2],at:3000),"dev mode firebombs have no cooldown")
        dev.spawn(1,kind:.rpg,at:300); for i in dev.soldiers.indices { dev.soldiers[i].selected = dev.soldiers[i].kind == .rpg }
        for i in dev.soldiers.indices { dev.soldiers[i].cooldown = 0 }
        check(dev.fireRockets(at:Vec(x:900,y:400)) == 1 && dev.fireRockets(at:Vec(x:900,y:400)) == 1,"dev mode RPGs fire without reloading")
        dev.score=World.requirement; let bankBefore=dev.bank; dev.extract()
        check(dev.bank == bankBefore,"dev mode banks nothing on extraction")
        dev.bank=5000; check(dev.withdraw(5000) == 0 && dev.bank == 5000,"dev mode never withdraws from the bank")
        dev.score=150_000; dev.reset(); check(dev.carriedCredits == 0,"dev mode points never carry into the next round")
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
        // Spalling concrete keeps loosening a little rubble off its bars, but nothing large comes down at once.
        check(town.chunks.map{ $0.cells.count }.reduce(0,+) < Int(World.toppleMass),"fire damage is gradual, not an instant collapse")
        // Balance: a one-off air strike must pay back its credits better than an RPG gunner,
        // who can be rearmed by cheap crates. Measured on the outpost bunker.
        func pointsPerCredit(_ cost: Int, seconds: Double, _ setup: (World) -> Void, step: (World) -> Void = { _ in }) -> Double {
            let w=World(); w.credits = 10_000; setup(w)
            for _ in 0..<Int(seconds*60) { step(w); w.update(1.0/60) }
            return Double(w.score)/Double(cost)
        }
        let bunkerX=1040.0
        var volley=0
        let rpgRate=pointsPerCredit(1200,seconds:90,{ w in
            w.spawn(1,kind:.rpg); w.soldiers[0].position=Vec(x:bunkerX-260,y:w.troopGround(at:bunkerX-260))
        },step:{ w in
            let x=bunkerX+Double(volley%3-1)*30
            if w.soldiers[0].cooldown <= 0 && w.fireRockets(at:Vec(x:x,y:w.ground(at:x)+10)) > 0 { volley+=1 }
        })
        let strafe=pointsPerCredit(gunRun.cost,seconds:90,{ $0.purchase(gunRun,at:bunkerX) })
        let napalm=pointsPerCredit(firebomb.cost,seconds:150,{ $0.purchase(firebomb,at:bunkerX) })
        print(String(format:"Points per credit on the bunker: RPG %.1f, gun run %.1f, firebombs %.1f",rpgRate,strafe,napalm))
        check(strafe > rpgRate*1.5 && napalm > rpgRate*1.3,"air strikes pay back more points per credit than an RPG gunner")
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
        check(lockout.refusal(firebomb) != nil,"firebombs stay locked for their 90 seconds")
        for _ in 0..<60 { lockout.update(1.0/60) }
        check(World.firebombCooldown == 90 && lockout.refusal(firebomb) == nil,"firebombs are available again after 90 seconds")
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
        // Reinforced concrete: bars cast through slabs and columns, bared by blasts and fire.
        let cast=World()
        let slabRow=(58-2-9)*S+1
        check(cast.rebar[cast.index(340*S,slabRow)] == World.barH && cast.rebar.contains(World.barV),"slabs carry horizontal bars and walls and columns vertical ones")
        check(cast.rebar[cast.index(270*S,World.bridgeDeck*S+1)] == 0 && cast.rebar[cast.index(428*S,30*S)] == 0,"bridge concrete and brick are unreinforced")
        cast.explode(at:Vec(x:340*World.cell*Double(S),y:Double(slabRow)*World.cell+World.top-2),radius:29)
        let bared=cast.voxels.indices.filter{ World.isBar(cast.voxels[$0]) }
        check(!bared.isEmpty && bared.allSatisfy{ cast.rebar[$0] == cast.voxels[$0] },"blasting reinforced concrete leaves its bars standing")
        check(!World.isStructure(World.barH) && World.points(World.barH) < World.points(3),"bare bars are not structure and score like rubble")
        func blasted(_ reinforcement: Double) -> Int {
            let w=World(); w.reinforcement=reinforcement
            let before=w.voxels.filter{ $0 == 3 }.count
            w.explode(at:Vec(x:356*World.cell*Double(S),y:Double(43*S)*World.cell+World.top),radius:29)
            return before-w.voxels.filter{ $0 == 3 }.count
        }
        check(blasted(3) < blasted(1) && blasted(1) < blasted(0),"better reinforced levels lose less concrete to each blast")
        // A slab holed through to its bars keeps hanging on them; cut the bars and it drops.
        func holed(bars: Bool) -> World {
            let w=World(); w.unit=S
            w.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
            w.fill(0,80,World.columns/S,World.rows/S-80,2)
            w.fill(46,52,2,28,3); w.fill(90,52,2,28,3); w.fill(46,50,46,2,3)
            w.layRebar()
            w.fill(60,50,4,2,0)
            w.unit=1
            if bars { for y in [50*S+1,50*S+2] { for x in 60*S..<64*S { w.voxels[w.index(x,y)]=World.barH } } }
            w.unit=S
            w.solveStructure()
            return w
        }
        check(holed(bars:true).material(66*S,50*S) == 3,"bars bridging a hole keep the slab beyond it up")
        check(holed(bars:false).material(66*S,50*S) == 0,"without its bars the far side of the hole falls")
        // A lone five-storey block whose west ground-floor bays are blasted out leans over
        // slowly about its east wall, snaps at a weak storey, and comes down on its side.
        let lean=World(); lean.unit=S
        lean.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        lean.fill(0,80,World.columns/S,World.rows/S-80,1)
        lean.building(100,20,5,80)
        lean.layRebar()
        lean.solveStructure()
        check(lean.chunks.isEmpty,"an intact reinforced block stands")
        // A wider block keeps standing on its interior column when one outer wall goes.
        let bay=World(); bay.unit=S
        bay.voxels = [UInt8](repeating:0,count:World.columns*World.rows)
        bay.fill(0,80,World.columns/S,World.rows/S-80,1)
        bay.building(100,34,3,80); bay.layRebar()
        bay.fill(100,80-9,9,7,0); bay.structureDirty=true
        for _ in 0..<60 { bay.update(1.0/60) }
        // Only the bare trim on the blasted face drops away.
        check(bay.chunks.allSatisfy{ $0.cells.count < 8*S*S } && bay.material(110*S,80*S-10*S) == 3,"losing one outer wall leaves a reinforced block standing on its column")
        bay.fill(100,80-9,18,7,0); bay.structureDirty=true
        for _ in 0..<30 { bay.update(1.0/60) }
        check(bay.chunks.contains{ $0.rooted },"losing its column too tips the block over")
        lean.fill(100,80-9,14,7,0); lean.structureDirty=true
        for _ in 0..<30 { lean.update(1.0/60) }
        check(lean.chunks.count == 1 && lean.chunks[0].rooted && lean.chunks[0].angle < 0 && lean.chunks[0].angle > -0.12,"an undercut block creaks over slowly toward the missing bays")
        var snappedApart=false, steepest=0.0
        for _ in 0..<240 {
            lean.update(1.0/60)
            if lean.chunks.filter({ $0.cells.count >= Int(World.toppleMass) }).count >= 2 { snappedApart=true }
            if let big=lean.chunks.filter({ $0.cells.count >= Int(World.toppleMass) && $0.hinge == nil }).map({ -$0.angle }).max() { steepest=max(steepest,big) }
        }
        check(snappedApart,"a leaning block snaps into separate sections")
        check(steepest > 1.2,"the section that breaks away comes down on its side (\(String(format:"%.2f",steepest)) rad)")
        for _ in 0..<600 { lean.update(1.0/60) }
        let wreck=(0..<World.columns).filter{ x in (0..<World.rows).contains{ lean.voxels[lean.index(x,$0)] == 10 } }
        check(lean.chunks.isEmpty && (wreck.min() ?? Int.max) < 85*S,"the wreck settles across the ground on the side it fell to")
        let binds=Keybinds()
        check(binds.action(for:12) == .support && binds.action(for:35) == .pause,"default keys: Q calls support, P still pauses")
        check(binds.bind(.extract,12) && binds.key(.extract) == 12 && binds.key(.support) == 7 && binds.action(for:12) == .extract,"binding a used key swaps the two actions")
        check(!binds.bind(.extract,53) && !binds.bind(.extract,18) && binds.key(.extract) == 12,"Esc and the number keys can't be bound")
        binds.bind(.pause,35)
        check(binds.action(for:49) == nil || binds.action(for:49) == .pause,"the old pause key is released or swapped when P takes pause")
        binds.resetAll()
        check(binds.isDefault && Set(KeyAction.allCases.map{binds.key($0)}).count == KeyAction.allCases.count,"reset restores defaults with no shared keys")
        // Operations: each later one is larger and harder, opens with a viable grant, and
        // stands, crosses and scores like the first.
        let specs=LevelSpec.all, firstShare=Double(specs[0].requirement)/Double(World().availablePoints)
        check(specs[0].name == "KESSEL CROSSING" && specs.count == 6,"six operations, opening at Kessel Crossing")
        for (i,spec) in specs.enumerated() {
            let name="OP-\(i+1) \(spec.name)"
            check(spec.grant >= World.openingFloor && spec.grant >= World.cost(of:spec.funds.kit),"\(name) opens with its \(spec.funds.name.lowercased()) kit and at least a rifle squad and a gun run")
            if i > 0 {
                let last=specs[i-1]
                check(spec.columns > last.columns && spec.lift > last.lift && spec.reinforcement > last.reinforcement && spec.requirement > last.requirement,"\(name) is wider, taller, better reinforced and asks more than the one before")
                check(spec.grant >= specs[0].grant,"\(name) never opens with less than the first operation")
            }
            World.select(i)
            let op=World()
            check(op.credits == spec.grant && op.reinforcement == spec.reinforcement && World.columns == spec.columns*S,"\(name) builds at its own size, reinforcement and grant")
            check(op.objectives.count == 6+i && op.objectives.allSatisfy{ $0.initial > 0 },"\(name) has \(6+i) objectives, each with structure to destroy")
            let share=Double(spec.requirement)/Double(op.availablePoints)
            check(share >= firstShare*0.95 && share <= firstShare*1.2,"\(name) asks for about the same share of its points as the first operation (\(Int(share*100))%)")
            check(op.transportAltitude+24 < op.skyline-200 && op.jetCruise >= World.top-World.skyHeight,"\(name) aircraft clear the tallest building and stay in camera reach")
            for _ in 0..<600 { op.update(1.0/60) }
            print("\(name) intact map detached blocks: \(op.collapsed)")
            check(op.collapsed == 0 && op.chunks.isEmpty,"\(name) intact map remains stable")
            // Every bridge drops into its river once a gap is blown through the deck.
            for k in op.objectives.indices where op.objectives[k].span {
                let o=op.objectives[k], deckY=Double(o.y0)*World.cell+World.top+2
                for n in 0..<40 where !op.objectives[k].destroyed {
                    op.explode(at:Vec(x:Double(o.x0+o.x1)/2*World.cell+Double(n%5-2)*20,y:deckY)); for _ in 0..<20 { op.update(1.0/60) }
                }
                for _ in 0..<900 { op.update(1.0/60) }
                // End bays may stay resting on the banks; the span between them must be gone.
                check(op.objectives[k].destroyed && op.spanCut(o),"\(name) \(o.name) is cut through and its span drops into the river")
            }
            // Troops can advance from the landing zone across every river to the last objective.
            let march=World(), goal=Double(march.objectives.last!.x0)*World.cell
            march.soldiers=[Soldier(id:1,position:Vec(x:300,y:march.troopGround(at:300)))]
            march.move(goal+40)
            for _ in 0..<Int(goal/TroopKind.rifleman.walkSpeed*60*1.5) where march.soldiers[0].position.x < goal { march.update(1.0/60) }
            check(march.soldiers[0].position.x >= goal,"\(name) troops reach \(march.objectives.last!.name) from the landing zone")
        }
        World.select(0)
        // Kamikaze drone: a cheap call-in that flies in from the edge, then follows the pointer.
        let droneOffer=World.support[3]
        check(droneOffer.kind == .drone && droneOffer.cost == 300,"a drone costs 300 credits")
        func pilotedDrone(at x: Double) -> World {
            let w=World(); w.credits=5_000; w.purchase(droneOffer,at:x)
            for _ in 0..<900 where w.drone?.piloted != true { w.update(1.0/60) }
            return w
        }
        let fly=World()
        check(fly.purchase(droneOffer,at:1200) && fly.drone != nil && fly.credits == World.startingCredits-droneOffer.cost,"a drone is launched")
        check(fly.drone!.heading == World.heading(toward:1200) && fly.drone!.position.x <= -World.edgeMargin,"the drone flies in from beyond the nearer edge")
        check(fly.refusal(droneOffer) != nil && fly.refusal(World.support[1]) == nil,"a drone locks only drones")
        check(!fly.detonateDrone() && fly.drone != nil,"a drone still off the map can't be set off")
        for _ in 0..<900 where fly.drone?.piloted != true { fly.update(1.0/60) }
        check(fly.drone?.piloted == true && abs(fly.drone!.position.x-1200) < 300,"the drone hands control over near its call-in point")
        // Flown sideways it leans into the move, keeps under its top speed, then settles in a hover.
        let hover=Vec(x:fly.drone!.position.x+300,y:fly.drone!.position.y+30)
        fly.steerDrone(toward:hover)
        var droneLean=0.0, fastest=0.0, overshoot=0.0
        for _ in 0..<300 {
            fly.update(1.0/60)
            guard let d=fly.drone else { break }
            droneLean=max(droneLean,d.tilt); fastest=max(fastest,hypot(d.velocity.x,d.velocity.y)); overshoot=max(overshoot,d.position.x-hover.x)
        }
        check(fly.drone != nil && droneLean > 0.4,"a drone leans into its move (\(droneLean))")
        check(fastest < World.droneTopSpeed*1.15,"a drone keeps near its top speed (\(Int(fastest)) px/s)")
        print("Drone hover: overshoot \(String(format:"%.1f",overshoot)) px, peak speed \(Int(fastest)) px/s")
        let settled=fly.drone!
        check(hypot(settled.position.x-hover.x,settled.position.y-hover.y) < 6 && hypot(settled.velocity.x,settled.velocity.y) < 15,"a piloted drone settles into a hover on the pointer")
        check(abs(settled.tilt) < 0.05 && abs(settled.throttle-1/2.2) < 0.05,"a hovering drone levels out and holds itself up against gravity")
        // The map's sides hold it in.
        let rim=pilotedDrone(at:300); rim.steerDrone(toward:Vec(x:-800,y:rim.drone!.position.y))
        for _ in 0..<300 { rim.update(1.0/60) }
        check(rim.drone != nil && rim.drone!.position.x >= 0,"a drone can't be flown off the map")
        // Flown into a building it detonates and blasts blocks.
        let strike=pilotedDrone(at:1200), before=strike.destroyed
        strike.steerDrone(toward:Vec(x:strike.drone!.position.x,y:World.bottom))
        for _ in 0..<600 where strike.drone != nil { strike.update(1.0/60) }
        check(strike.drone == nil && strike.destroyed > before && !strike.blasts.isEmpty,"a drone flown into the ground detonates and blasts blocks (\(strike.destroyed-before))")
        for _ in 0..<Int(World.droneCooldownTime*60) { strike.update(1.0/60) }
        check(strike.refusal(droneOffer) == nil,"another drone can be called once it is gone and the cooldown is over")
        // Detonated by the player in the air.
        let pop=pilotedDrone(at:1200), popped=pop.drone!.position
        check(pop.detonateDrone() && pop.drone == nil && pop.blasts.contains{ hypot($0.position.x-popped.x,$0.position.y-popped.y) < 1 },"a piloted drone detonates on command")
        // A flat battery cuts the motors; the drone falls and goes off where it lands.
        let flat=pilotedDrone(at:1200)
        flat.steerDrone(toward:flat.drone!.position)
        var flown=0.0, cut=false
        for _ in 0..<Int((World.droneBattery+15)*60) where flat.drone != nil {
            flat.update(1.0/60); flown += 1.0/60
            if let d=flat.drone, !d.powered { cut = cut || d.throttle == 0 }
        }
        check(cut && flat.drone == nil && flown > World.droneBattery,"a drone with a flat battery falls and detonates (\(String(format:"%.1f",flown)) s)")
        // Flown into water a drone shorts out: no blast, and its wreck sinks to the bottom.
        let dunk=pilotedDrone(at:1200)
        dunk.steerDrone(toward:dunk.drone!.position)
        for _ in 0..<150 { dunk.update(1.0/60) }
        let over=dunk.drone!.position
        let cx=Int(over.x/World.cell), cy=40
        dunk.unit=1; dunk.fill(cx-40,0,81,cy+60,0); dunk.fill(cx-34,cy+56,69,4,2); dunk.fill(cx-34,cy+30,4,26,2); dunk.fill(cx+31,cy+30,4,26,2)
        for y in cy+34..<cy+56 { for x in cx-30..<cx+31 { dunk.setWater(dunk.index(x,y),1) } }
        dunk.structureDirty=false
        let intact=dunk.destroyed
        dunk.steerDrone(toward:Vec(x:over.x,y:Double(cy+50)*World.cell+World.top))
        for _ in 0..<600 where dunk.drone != nil { dunk.update(1.0/60) }
        check(dunk.drone == nil && dunk.wrecks.count == 1 && dunk.destroyed == intact && dunk.blasts.isEmpty,"a drone flown into water shorts out without exploding")
        check(dunk.wrecks[0].shorted && !dunk.wrecks[0].powered && !dunk.detonateDrone(),"a shorted drone is dead and can't be set off")
        for _ in 0..<600 { dunk.update(1.0/60) }
        let floorY=Double(cy+56)*World.cell+World.top
        check(dunk.droneInWater(dunk.wrecks[0].position) && floorY-dunk.wrecks[0].position.y < 12 && dunk.wrecks[0].resting > 1,"its wreck sinks and comes to rest on the bottom")
        check(dunk.refusal(droneOffer) == nil,"another drone can be called once the cooldown is over")
        // Cooldown and one at a time.
        let lock=World(); lock.credits=5_000; lock.purchase(droneOffer,at:1200)
        check(lock.refusal(droneOffer) != nil && !lock.purchase(droneOffer,at:1400),"only one drone flies at a time")
        for _ in 0..<Int(World.droneCooldownTime*60)+10 { lock.update(1.0/60) }
        check(lock.refusal(droneOffer) == "DRONE AIRBORNE","the cooldown alone doesn't free a second drone")
        lock.detonateDrone(); check(lock.refusal(droneOffer) == nil,"a drone can be called again after the last one blows")
        lock.purchase(droneOffer,at:1200); lock.reset(); check(lock.drone == nil && lock.droneCooldown == 0,"reset clears the drone and its cooldown")
        let career=World()
        check(career.unlocked(0) && !career.unlocked(1),"only the first operation is open at the start")
        career.score=World.requirement; career.extract()
        check(career.cleared == 1 && career.unlocked(1) && !career.unlocked(2),"extracting clears the operation and opens the next")
        career.reset(); check(career.cleared == 1,"progress survives a new round")
        career.devMode=true; check(specs.indices.allSatisfy{ career.unlocked($0) },"dev mode opens every operation")
        World.select(2); career.devMode=false; career.reset(); career.score=World.requirement; career.extract()
        check(career.cleared == 3,"clearing a later operation opens the one after it")
        World.select(0)
        // Water: every operation's lakes and rivers lie still until something disturbs them.
        for level in specs.indices {
            World.select(level)
            let still=World(), before=still.water.mass, voxels=still.voxels
            for _ in 0..<600 { still.update(1.0/60) }
            var moved: Float=0
            for i in before.indices where before[i] > 0 { moved += abs(before[i]-still.water.mass[i]) }
            check(before.contains{ $0 > 0 } && moved < 1 && still.water.active.isEmpty && still.voxels == voxels,"\(specs[level].name) water lies still (\(String(format:"%.2f",moved)) moved)")
        }
        World.select(0)
        // A stone tank of water on bedrock (which neither drinks water nor lets it through), with
        // an empty basin beside it.
        func tank() -> World {
            let t=World()
            t.voxels=[UInt8](repeating:0,count:World.columns*World.rows); t.backdrops=[Int](repeating:-1,count:World.columns*World.rows)
            t.unit=1; t.fill(0,200,World.columns,World.rows-200,2); t.fill(400,160,4,40,2); t.fill(480,160,4,40,2); t.fill(640,150,4,50,2)
            t.pools=[]; t.seedWater()
            for y in 170..<200 { for x in 404..<480 { t.setWater(t.index(x,y),1) } }
            t.structureDirty=false
            for _ in 0..<120 { t.update(1.0/60) }
            return t
        }
        func total(_ t: World) -> Float { t.water.mass.reduce(0,+)+t.water.drops.map{$0.mass}.reduce(0,+) }
        let breach=tank(), held=total(breach)
        breach.unit=1; breach.fill(480,160,4,40,0)
        var outside: Float=0
        for _ in 0..<120 { breach.update(1.0/60) }
        for i in breach.water.mass.indices where i%World.columns > 484 && i%World.columns < 640 { outside += breach.water.mass[i] }
        check(outside > held*0.2,"water floods out through a breached wall within two seconds (\(Int(outside)) of \(Int(held)) cells)")
        for _ in 0..<1800 { breach.update(1.0/60) }
        check(abs(total(breach)-held) < held*0.03,"flowing water is conserved (\(Int(total(breach))) of \(Int(held)))")
        // Its surface across the tank and basin levels out, leaving at most a few ripples moving.
        let levels=(406..<638).map{ x -> Float in
            var y=199; var depth: Float=0
            while y > 150 && breach.water.mass[breach.index(x,y)] > 0.002 { depth += min(1,breach.water.mass[breach.index(x,y)]); y -= 1 }
            return depth
        }
        let spread=(levels.max() ?? 0)-(levels.min() ?? 0)
        check(spread < 1 && breach.water.active.count < 1000,"spilled water levels out and settles (surface within \(String(format:"%.2f",spread)) cells, \(breach.water.active.count) still rippling)")
        let surge=tank(), contained=total(surge)
        surge.explode(at:Vec(x:442*World.cell,y:196*World.cell+World.top),radius:30)
        check(surge.water.drops.count > 20,"a blast under water throws it into the air (\(surge.water.drops.count) drops)")
        check(surge.water.drops.contains{ $0.velocity.y < -250 },"an underwater burst sends up a column")
        for _ in 0..<900 { surge.update(1.0/60) }
        check(surge.water.drops.isEmpty && abs(total(surge)-contained) < contained*0.03,"thrown water falls back into the grid (\(Int(total(surge))) of \(Int(contained)))")
        // Dry soil drinks water that touches it, darkening, and the damp wicks on into the ground.
        let soil=tank()
        soil.unit=1; soil.fill(404,190,76,10,1)
        for i in soil.water.mass.indices where soil.voxels[i] != 0 { soil.water.mass[i]=0; soil.water.next[i]=0 }
        for x in 404..<480 { soil.wakeWater(soil.index(x,189)) }
        let poured=total(soil)
        for _ in 0..<600 { soil.update(1.0/60) }
        let surface=soil.index(440,190), deeper=soil.index(440,193)
        check(soil.water.soak[surface] > 0.9 && soil.water.wet[surface] >= 3,"soil under water soaks up and darkens")
        check(soil.water.soak[deeper] > 0,"damp wicks down into the ground below")
        check(total(soil) < poured-10,"soaking uses up water (\(Int(poured-total(soil))) cells drunk)")
        // Rubble landing in water lifts it, and lets it seep through.
        let sink=tank(), level=total(sink)
        let spot=sink.index(442,199)
        sink.voxels[spot]=10; sink.displaceWater(spot)
        for _ in 0..<60 { sink.update(1.0/60) }
        check(abs(total(sink)-level) < 1 && sink.water.mass[spot] <= World.rubblePorosity+0.01,"rubble displaces the water it lands in")
        let plug=tank()
        plug.unit=1; plug.fill(480,160,4,40,10)
        for y in 160..<200 { for x in 480..<484 { plug.water.mass[plug.index(x,y)]=0; plug.water.next[plug.index(x,y)]=0 } }
        for y in 170..<200 { plug.wakeWater(plug.index(479,y)) }
        for _ in 0..<600 { plug.update(1.0/60) }
        var seeped: Float=0
        for i in plug.water.mass.indices where i%World.columns > 484 && i%World.columns < 640 { seeped += plug.water.mass[i] }
        check(seeped > 5,"water seeps through a rubble pile (\(Int(seeped)) cells)")
        // Water puts out fire and keeps soaked fuel from catching.
        let douse=tank(), wetCell=douse.index(442,195)
        douse.backdrops[wetCell]=douse.index(442,200)
        douse.ignite(wetCell,1)
        douse.stepFire(0.1)
        check(douse.fire.flame[wetCell] == 0 && !douse.fire.burning.contains(wetCell),"water floods out a fire")
        // Breaching the Stausee dam on Irongate Pass sends the reservoir down the valley.
        World.select(2)
        let dam=World()
        dam.unit=S; dam.fill(756,40,30,50,0); dam.unit=1; dam.structureDirty=true
        for _ in 0..<600 { dam.update(1.0/60) }
        var valley: Float=0
        for i in dam.water.mass.indices where i%World.columns > 790*S && i%World.columns < 840*S { valley += dam.water.mass[i] }
        check(valley > 500,"a breached dam floods the valley below it (\(Int(valley)) cells)")
        World.select(0)
        print("All structural physics checks passed. Peak scenario ended with \(stress.chunks.count) moving chunks.")
    }
}
