import Foundation

// The later fronts. Each is its own country with its own landmarks, laid out west to east
// in design units on terrain from `World.terrain(for:)`. Level 1 (Kessel Crossing) is
// built in `Levels.swift`.
extension World {
    // MARK: Marrow Ferry: a port on the Marrow Sound

    static let marrowTerrain: [(x: Int, row: Int)] = [(0,64),(60,64),(95,65),(175,65),(200,67),(212,67),(224,89),(280,89),(292,67),
                                                       (476,67),(486,85),(586,85),(596,67),(760,67),(790,64),(864,64)]
    func marrowFerry() {
        let g = 67
        coastguard(104, base: 65)
        // Steel tank traps along the beach.
        for x in stride(from:172, to:204, by:7) { taper(x, 4, base: surfaceRow(x+2), top: surfaceRow(x+2)-3, 11) }
        swingBridge()
        customsHouse(304, base: g)
        // Warehouse row: tall brick stores under steep roofs, a hoist beam at each gable.
        for (k,x) in [356,394,432].enumerated() {
            let eave = house(x, 34, 3+k%2, base: g, story: 8, pitch: 1, bay: 16)
            fill(x+15, eave-12, 4, 2, 11)
        }
        fill(470, g-3, 4, 3, 7); fill(465, g-2, 4, 2, 7)
        freighter(494, bed: 85)
        pools.append(Pool(x0:476,x1:596,row:g+2))
        cranes(600, base: g)
        oilTerminal(650, base: g)
        lighthouse(806, base: 64)
        landmarks += [Landmark(name:"LZ / DUNES",x:200,y:560),Landmark(name:"MARROW SOUND",x:2000,y:640),
                      Landmark(name:"CUSTOMS QUAY",x:2700,y:330),Landmark(name:"WAREHOUSE ROW",x:3300,y:330),
                      Landmark(name:"INNER BASIN",x:4300,y:330),Landmark(name:"OIL TERMINAL",x:5600,y:420),Landmark(name:"BREAKWATER",x:6500,y:250)]
    }
    /// Coastguard station: a gabled brick house, a lookout tower with a glazed watch room,
    /// and a lattice signal mast with a yard and flag.
    func coastguard(_ x: Int, base: Int) {
        fill(x-4, base, 50, 4, 1)
        house(x, 26, 2, base: base, story: 9)
        let top = base-36
        fill(x+27, top, 8, base-top, 3); reinforce(x+26, base-1, 10, 3)
        fill(x+27, top-8, 1, 8, 11); fill(x+34, top-8, 1, 8, 11)
        fill(x+28, top-7, 6, 7, 4); fill(x+26, top-9, 10, 2, 3)
        lattice(x+38, 3, top: 8, base: base)
        fill(x+35, 14, 9, 1, 11); fill(x+39, 2, 1, 6, 11); fill(x+40, 2, 4, 3, 5)
        target("COASTGUARD STATION",x,2,x+44,base,1500)
    }
    /// Swing bridge over the Marrow Sound: a steel truss span on a pivot pier, the
    /// operator's cabin on top, and abutments on each bank.
    func swingBridge() {
        let deck = 65, bed = 89
        fill(204, deck, 96, 2, 12)
        footTo(204, 14, top: deck+2, 12); footTo(288, 12, top: deck+2, 12)
        reinforce(204, deck, 14, 6); reinforce(288, deck, 12, 6)
        fill(248, deck+2, 8, bed-deck-2, 12); fill(245, bed, 14, 3, 12); reinforce(245, bed-4, 14, 7)
        for x in stride(from:216, through:288, by:8) { fill(x, deck-10, 1, 10, 11) }
        fill(216, deck-10, 73, 1, 11); fill(216, deck-5, 73, 1, 11)
        fill(248, deck-16, 8, 6, 5); fill(250, deck-14, 4, 3, 4); fill(247, deck-17, 10, 1, 11)
        pools.append(Pool(x0:212,x1:292,row:69))
        target("SWING BRIDGE",218,deck,288,deck+2,5000,span:bed)
    }
    /// Customs house: two brick storeys over an arcade of columns, a pediment, and a
    /// clock cupola.
    func customsHouse(_ x: Int, base: Int) {
        reinforce(x-1, base-1, 44, 3)
        colonnade(x, 42, base: base, h: 10, every: 6)
        room(x+2, base-8, x+39, base-1, floor: base, ceiling: base-9)
        let eave = house(x, 42, 2, base: base-10, story: 9, pitch: 3, bay: 14)
        fill(x+17, eave-12, 8, 6, 5); fill(x+19, eave-11, 4, 4, 4)
        dome(Double(x)+21, base: eave-12, 6, 11, thick: 0)
        fill(x+20, eave-22, 2, 5, 11)
        target("CUSTOMS HOUSE",x,eave-22,x+42,base,3000)
    }
    /// SS Alderney at her berth: a steel hull with a raked bow resting on the basin floor,
    /// holds of cargo, a bridge house, a funnel and two masts.
    func freighter(_ x: Int, bed: Int) {
        let deckRow = 63, w = 88
        // Ballasted hull below the waterline, then hollow holds under the main deck.
        for y in 72..<bed { let inset = max(0,y-80); fill(x+inset, y, w-2*inset, 1, 11) }
        for y in deckRow..<72 { let rake = max(0,(72-y)*4/9); fill(x, y, w+rake, 1, 11) }
        for (x0,x1) in [(x+2,x+22),(x+24,x+44),(x+46,x+62)] {
            fill(x0, deckRow+2, x1-x0, 70-deckRow-2, 0)
            room(x0, deckRow+2, x1-1, 69, floor: 70, ceiling: deckRow+1)
            fill(x0+2, 66, 6, 4, 7); fill(x0+9, 67, 6, 3, 7)
        }
        fill(x+66, deckRow-14, 16, 14, 3)
        fill(x+66, deckRow-14, 16, 1, 11)
        for r in 0..<3 { fill(x+68, deckRow-12+r*4, 12, 2, 4) }
        fill(x+64, deckRow-16, 20, 2, 3)
        fill(x+70, deckRow-28, 7, 12, 11); fill(x+70, deckRow-24, 7, 2, 5)
        // Masts stand over the bulkheads between the holds.
        fill(x+22, deckRow-22, 2, 22, 11); fill(x+18, deckRow-18, 10, 1, 11)
        fill(x+44, deckRow-20, 2, 20, 11); fill(x+40, deckRow-16, 10, 1, 11)
        target("SS ALDERNEY",x,deckRow-28,x+w+6,bed,4000)
    }
    /// Two gantry cranes on the east quay with their jibs out over the basin.
    func cranes(_ x: Int, base: Int) {
        for cx in [x, x+22] {
            reinforce(cx-1, base-1, 16, 3)
            fill(cx, base-30, 2, 30, 11); fill(cx+12, base-30, 2, 30, 11)
            for y in stride(from:base-26, to:base, by:8) { fill(cx, y, 14, 1, 11) }
            fill(cx-8, base-32, 24, 2, 11)
            fill(cx+3, base-38, 8, 6, 5); fill(cx+4, base-36, 3, 2, 4)
            fill(cx+6, base-44, 1, 6, 11); fill(cx-2, base-44, 9, 1, 11)
            fill(cx-7, base-30, 1, 5, 11)
        }
        target("HARBOUR CRANES",x-8,base-44,x+36,base,3500)
    }
    /// Oil terminal: three storage tanks joined by a pipe rack.
    func oilTerminal(_ x: Int, base: Int) {
        tank(x, 26, 22, base: base); tank(x+32, 30, 26, base: base); tank(x+70, 24, 20, base: base)
        for px in [x+27, x+65, x+96, x+104] { fill(px, base-10, 1, 10, 11) }
        fill(x+26, base-10, 6, 1, 11); fill(x+26, base-7, 6, 1, 11)
        fill(x+62, base-10, 8, 1, 11); fill(x+94, base-10, 12, 1, 11); fill(x+94, base-7, 12, 1, 11)
        target("OIL TERMINAL",x,base-28,x+106,base,4500)
    }
    /// Marrow Light on the breakwater: a tapering brick tower, a steel gallery, a glazed
    /// lantern between corner posts, and the keeper's cottage.
    func lighthouse(_ x: Int, base: Int) {
        fill(x-6, base-2, 60, 2, 1); fill(x+42, base-4, 12, 2, 2)
        house(x, 16, 1, base: base-2, story: 9, pitch: 1)
        let tx = x+24, top = 18
        fill(tx-1, base-2, 16, 2, 3); reinforce(tx-1, base-3, 16, 3)
        taper(tx, 14, base: base-2, top: top, tip: 8, 5)
        for y in stride(from:top+8, to:base-6, by:12) { fill(tx+5, y, 4, 3, 4) }
        fill(tx+1, top-1, 12, 1, 11)
        fill(tx+3, top-7, 1, 6, 11); fill(tx+10, top-7, 1, 6, 11); fill(tx+4, top-6, 6, 5, 4)
        taper(tx+2, 10, base: top-7, top: top-11, tip: 2, 11)
        fill(tx+6, top-14, 2, 3, 11)
        target("MARROW LIGHT",x,top-14,tx+16,base,5000)
    }
}

extension World {
    // MARK: Irongate Pass: a mountain road to the border fortress

    static let irongateTerrain: [(x: Int, row: Int)] = [(0,75),(100,76),(175,76),(205,64),(225,58),(330,58),(338,48),(390,24),(410,24),(462,48),
                                                         (470,58),(492,58),(514,100),(598,100),(620,58),(650,58),(670,90),(776,90),(786,96),(800,96),
                                                         (840,58),(860,40),(890,40),(910,58),(1008,58)]
    func irongatePass() {
        checkpoint(100, base: 76)
        kurhaus(240, base: 58)
        railTunnel()
        summitRadar(392)
        schwarzViaduct()
        staudamm()
        casemates()
        irongate(912, base: 58)
        landmarks += [Landmark(name:"LZ / MEADOW",x:200,y:690),Landmark(name:"KURHAUS",x:2200,y:290),Landmark(name:"IRONGATE TUNNEL",x:3200,y:420),
                      Landmark(name:"SCHWARZ GORGE",x:4400,y:700),Landmark(name:"STAUSEE",x:5600,y:560),Landmark(name:"CASEMATES",x:6900,y:330),
                      Landmark(name:"IRONGATE",x:7700,y:120)]
    }
    /// Border checkpoint: a guard hut, the barrier, a lattice watchtower with its cabin and
    /// searchlight, the customs shed, and sandbag nests.
    func checkpoint(_ x: Int, base: Int) {
        house(x+4, 18, 1, base: base, story: 9)
        fill(x+26, base-5, 2, 5, 11); fill(x+28, base-5, 8, 1, 11); fill(x+38, base-3, 2, 3, 11)
        reinforce(x+40, base-1, 14, 3)
        lattice(x+42, 8, top: base-30, base: base)
        fill(x+41, base-2, 10, 2, 3)
        fill(x+40, base-36, 12, 6, 3); fill(x+42, base-35, 8, 3, 4)
        taper(x+39, 14, base: base-36, top: base-40, tip: 2, 11)
        fill(x+50, base-33, 4, 2, 11)
        house(x+56, 22, 1, base: base, story: 10, 3, pitch: 4)
        fill(x+2, base-2, 3, 2, 6); fill(x-12, base-2, 8, 2, 6); fill(x-10, base-4, 4, 2, 6)
        target("BORDER CHECKPOINT",x+2,base-42,x+80,base,1500)
    }
    /// Kurhaus sanatorium: a long three-storey brick spa hotel with balconies at each end
    /// and a central tower under a pyramid roof.
    func kurhaus(_ x: Int, base: Int) {
        let eave = house(x, 72, 3, base: base, story: 9, pitch: 2, bay: 14)
        for f in 1...3 { fill(x-3, base-2-f*9+2, 3, 1, 11); fill(x+72, base-2-f*9+2, 3, 1, 11) }
        let top = eave-12
        fill(x+30, top, 12, eave-top, 5); fill(x+30, top, 12, 2, 3)
        for y in stride(from:top+4, to:eave-3, by:7) { fill(x+33, y, 6, 4, 4) }
        taper(x+29, 14, base: top, top: top-9, tip: 2, 11)
        fill(x+35, top-13, 2, 4, 11)
        target("KURHAUS SANATORIUM",x-3,top-13,x+75,base,3000)
    }
    /// Rail tunnel through the summit: a concrete-lined bore on close-set columns, with a
    /// portal arch at each end.
    func railTunnel() {
        fill(330, 49, 141, 9, 0)
        fill(328, 48, 145, 3, 3)
        for cx in stride(from:344, through:454, by:8) { fill(cx, 51, 3, 7, 3) }
        for (px,dir) in [(330,1),(462,-1)] {
            let pillar = dir > 0 ? px : px+6
            fill(pillar, 42, 3, 16, 3)
            fill(px, 42, 9, 7, 3); fill(px, 40, 9, 2, 5)
        }
        target("IRONGATE TUNNEL",330,40,471,58,3500)
    }
    /// Radar station on the summit: a radome on its equipment hut and a lattice antenna mast.
    func summitRadar(_ x: Int) {
        let ground = 24
        footTo(x, 16, top: ground-8, 3); fill(x+2, ground-6, 12, 4, 0)
        room(x+2, ground-6, x+13, ground-3, floor: ground-2, ceiling: ground-7)
        disc(Double(x)+8, Double(ground)-15, 7, 3)
        let mast = x+20, foot = surfaceRow(mast+1)
        lattice(mast, 3, top: 2, base: foot)
        fill(mast-3, 6, 9, 1, 11); fill(mast-2, 12, 7, 1, 11)
        target("SUMMIT RADAR",x,1,mast+6,foot,4000)
    }
    /// Schwarz viaduct: a stone-arched railway bridge across the gorge on four tall piers.
    func schwarzViaduct() {
        let deck = 58, bed = 100
        fill(484, deck, 144, 2, 12)
        footTo(484, 10, top: deck+2, 12); footTo(618, 10, top: deck+2, 12)
        reinforce(484, deck, 10, 8); reinforce(618, deck, 10, 8)
        let piers = [518,542,566,590]
        for px in piers {
            fill(px, deck+2, 4, bed-deck-2, 12); fill(px-2, bed, 8, 3, 12); reinforce(px-2, bed-4, 8, 7)
        }
        // Arched spandrels: thick over each pier, thinning to the crown of each arch.
        let supports = [494]+piers+[618]
        for k in 0..<(supports.count-1) {
            let a = supports[k]+(k == 0 ? 0 : 4), b = supports[k+1], mid = Double(a+b)/2, half = Double(b-a)/2
            for x in a..<b {
                let t = abs(Double(x)+0.5-mid)/half, depth = Int((t*t*12).rounded())
                if depth > 0 { fill(x, deck+2, 1, depth, 12) }
            }
        }
        target("SCHWARZ VIADUCT",494,deck,618,deck+2,6000,span:bed)
    }
    /// Stausee dam: a concrete gravity dam across the valley, a valve house on its crest,
    /// and the reservoir behind it.
    func staudamm() {
        let x = 760, bed = 90, crest = 60
        fill(x-2, bed, 22, 3, 3); reinforce(x-2, bed-1, 22, 4)
        for y in crest..<bed {
            let t = Double(y-crest)/Double(bed-crest), w = Int(6+t*12)
            fill(x, y, w, 1, 3)
        }
        fill(x, crest-1, 1, 1, 11); fill(x+5, crest-1, 1, 1, 11)
        fill(x+1, crest-6, 5, 5, 5); fill(x+2, crest-5, 2, 2, 4); gable(x, 7, eave: crest-6, 11, pitch: 1)
        for y in stride(from:crest+6, to:bed-4, by:8) { fill(x+3, y, 2, 2, 4) }
        pools.append(Pool(x0:650,x1:760,row:64))
        target("STAUSEE DAM",x,crest-10,x+18,bed,4500)
    }
    /// Gun casemates cut into the knoll's west face, and an armoured cupola on top.
    func casemates() {
        for (k,cx) in [842,852,862].enumerated() {
            let ground = surfaceRow(cx+12)
            footTo(cx, 13, top: ground-9, 3); fill(cx+2, ground-7, 9, 5, 0)
            room(cx+2, ground-7, cx+10, ground-3, floor: ground-2, ceiling: ground-8)
            fill(cx, ground-6, 2, 2, 0); fill(cx-5, ground-5, 6, 1, 11)
            if k == 2 { fill(cx+4, ground-12, 6, 3, 3) }
        }
        fill(870, 36, 12, 4, 3); dome(876, base: 36, 4, 11); fill(874, 34, 2, 1, 0); fill(868, 34, 5, 1, 11)
        target("ALPINE CASEMATES",836,28,884,60,4500)
    }
    /// The Irongate: two brick towers astride the road joined by a gatehouse over the gate,
    /// crenellated, with curtain walls and the garrison's barracks behind.
    func irongate(_ x: Int, base: Int) {
        let top = 16
        for tx in [x+12, x+44] {
            reinforce(tx-1, base-1, 18, 3)
            fill(tx, top, 16, base-top, 5)
            fill(tx+3, top+3, 10, base-top-6, 0)
            room(tx+3, top+3, tx+12, base-4, floor: base-3, ceiling: top+2)
            for f in stride(from:top+12, to:base-2, by:12) { fill(tx+3, f, 10, 1, 3); fill(tx+5, f-3, 6, 3, 4) }
            for k in 0..<4 { fill(tx+k*4, top-3, 2, 3, 5) }
        }
        fill(x+28, top+10, 16, 22, 5); fill(x+31, top+13, 10, 16, 0)
        room(x+31, top+13, x+40, top+28, floor: top+29, ceiling: top+12)
        for k in 0..<4 { fill(x+28+k*4, top+7, 2, 3, 5) }
        fill(x+35, top-12, 1, 12+10, 11); fill(x+36, top-12, 5, 3, 5)
        for wx in [x, x+60] { fill(wx, base-8, 12, 8, 5); for k in 0..<3 { fill(wx+k*4, base-10, 2, 2, 5) } }
        house(x+76, 20, 2, base: base, story: 9, pitch: 2)
        target("IRONGATE FORT",x,top-12,x+96,base,6000)
    }
}

extension World {
    // MARK: Vestra Works: the steel town

    static let vestraTerrain: [(x: Int, row: Int)] = [(0,84),(90,85),(420,85),(430,101),(490,101),(500,85),(1070,85),(1110,64),(1152,62)]
    func vestraWorks() {
        let g = 85
        waterTower(100, base: g)
        railYard(160, base: g)
        gasholder(340, base: g)
        liftBridge()
        blastFurnace(516, base: g)
        coolingTower(680, base: g); coolingTower(736, base: g)
        target("COOLING TOWERS",660,22,756,g,6000)
        powerHouse(776, base: g)
        cokeWorks(890, base: g)
        directorate(1010, base: g)
        landmarks += [Landmark(name:"LZ / SLAG FIELD",x:200,y:760),Landmark(name:"RAIL YARD",x:1900,y:560),Landmark(name:"GASWORKS",x:2800,y:300),
                      Landmark(name:"VESTRA CANAL",x:3500,y:780),Landmark(name:"FURNACE ROW",x:4400,y:250),Landmark(name:"POWER STATION",x:6000,y:200),
                      Landmark(name:"COKE WORKS",x:7400,y:450),Landmark(name:"DIRECTORATE",x:8300,y:300)]
    }
    /// Water tower: a riveted steel tank on two lattice legs, and its brick pump house.
    func waterTower(_ x: Int, base: Int) {
        for lx in [x+3, x+15] { lattice(lx, 3, top: base-40, base: base, rung: 5) }
        fill(x+3, base-24, 15, 1, 11)
        let top = base-56
        fill(x, top, 21, 16, 11); fill(x+2, top+2, 17, 12, 0)
        room(x+2, top+2, x+18, top+13, floor: top+14, ceiling: top+1)
        for y in [top+5, top+10] { fill(x, y, 21, 1, 11) }
        // The tank is full: one pool in each compartment between the hoops.
        for row in [top+3, top+6, top+11] { pools.append(Pool(x0:x+2,x1:x+18,row:row)) }
        taper(x, 21, base: top, top: top-6, tip: 3, 11)
        fill(x+10, top-9, 1, 3, 11)
        house(x+28, 18, 1, base: base, story: 9)
        target("WATER TOWER",x,top-9,x+46,base,1500)
    }
    /// A steam locomotive standing on the rails at row `rail`, facing east.
    func locomotive(_ x: Int, rail: Int) {
        fill(x, rail-1, 30, 1, 11)
        for wx in [x+3, x+9, x+15, x+21] { fill(wx, rail-3, 3, 2, 11) }
        fill(x+1, rail-5, 28, 2, 11)
        fill(x+12, rail-10, 17, 5, 11); fill(x+25, rail-13, 2, 3, 11); fill(x+18, rail-12, 4, 2, 11)
        fill(x+2, rail-14, 9, 9, 11); fill(x+4, rail-12, 5, 3, 4); fill(x+1, rail-15, 11, 1, 11)
    }
    /// Rail yard: freight wagons on the sidings, the locomotive shed with an engine inside,
    /// and a signal gantry.
    func railYard(_ x: Int, base: Int) {
        let rail = base-1
        fill(x, rail, 170, 1, 11)
        for wx in [x+2, x+20, x+38] {
            fill(wx+1, rail-2, 3, 2, 11); fill(wx+10, rail-2, 3, 2, 11)
            fill(wx, rail-8, 15, 6, 11); fill(wx+1, rail-7, 13, 4, 7)
        }
        let shed = x+66
        house(shed, 66, 1, base: base, story: 20, pitch: 2, bay: 16, panes: false)
        locomotive(shed+20, rail: base-2)
        for wx in [shed+4, shed+52] { fill(wx, base-10, 6, 8, 4) }
        for px in [x+148, x+164] { fill(px, base-22, 2, 22, 11) }
        fill(x+146, base-22, 22, 2, 11)
        for lx in [x+151, x+156, x+161] { fill(lx, base-20, 2, 3, 5) }
        target("LOCOMOTIVE SHED",shed-1,base-48,shed+67,base,3000)
    }
    /// Gasholder: a lattice guide frame of columns and ring girders around the bell.
    func gasholder(_ x: Int, base: Int) {
        let top = base-46
        for cx in stride(from:x, through:x+66, by:11) { fill(cx, top, 2, base-top, 11) }
        for y in stride(from:top, to:base-4, by:9) { fill(x, y, 68, 1, 11) }
        tank(x+4, 60, 20, base: base)
        target("GASHOLDER No. 3",x,top-2,x+68,base,3500)
    }
    /// Lift bridge over the Vestra canal: a deck on a mid-channel pier between two
    /// machinery towers with counterweights.
    func liftBridge() {
        let deck = 83, bed = 101
        for tx in [413, 500] {
            reinforce(tx-1, deck+1, 9, 4)
            fill(tx, 50, 7, deck+2-50, 3); fill(tx+2, 54, 3, 24, 0)
            room(tx+2, 54, tx+4, 77, floor: 78, ceiling: 53)
            fill(tx-1, 44, 9, 6, 5); fill(tx+1, 46, 5, 2, 4); gable(tx-2, 11, eave: 44, 11, pitch: 2)
            fill(tx+3, 56, 1, 8, 11); fill(tx+2, 64, 3, 3, 11)
        }
        fill(413, deck, 94, 2, 12)
        fill(456, deck+2, 8, bed-deck-2, 12); fill(453, bed, 14, 3, 12); reinforce(453, bed-4, 14, 7)
        for x in stride(from:422, through:496, by:6) { fill(x, deck-3, 1, 3, 11) }
        fill(420, deck-3, 80, 1, 11)
        pools.append(Pool(x0:420,x1:500,row:87))
        target("LIFT BRIDGE",420,deck,500,deck+2,5500,span:bed)
    }
    /// Blast furnace: the steel-clad stack and its gas main, three domed brick stoves, the
    /// cast house, and a skip hoist on trestles up to the furnace top.
    func blastFurnace(_ x: Int, base: Int) {
        let fx = x+40, top = base-58
        reinforce(fx-3, base-1, 22, 3)
        taper(fx, 16, base: base, top: top, tip: 10, 11)
        fill(fx+3, top+6, 10, 30, 5)
        fill(fx+4, top-8, 2, 8, 11); fill(fx+10, top-8, 2, 8, 11); fill(fx+4, top-9, 8, 1, 11)
        for (k,sx) in [fx+24, fx+38, fx+52].enumerated() {
            fill(sx, base-44+k*2, 10, 44-k*2, 5); dome(Double(sx)+5, base: base-44+k*2, 5, 5)
            fill(sx+4, base-30, 2, 4, 4)
        }
        fill(fx+12, top+2, 50, 2, 11)
        for sx in [fx+24, fx+38, fx+52] { fill(sx+4, top+4, 2, base-44-top-4, 11) }
        house(x, 30, 1, base: base, story: 12, pitch: 2)
        // Skip hoist: a stepped incline braced by trestles every few columns.
        for k in 0..<36 {
            let cx = x+4+k, row = base-14-k*44/36
            fill(cx, row, 2, 2, 11)
            if k%5 == 0 { footTo(cx, 1, top: row+2, 11) }
        }
        target("BLAST FURNACE No. 2",x,top-9,fx+62,base,4500)
    }
    /// Hyperbolic cooling tower centred on column `cx`: a two-cell concrete shell pinched at
    /// the throat and flaring at the lip.
    func coolingTower(_ cx: Int, base: Int) {
        let height = 60
        reinforce(cx-20, base-1, 41, 3)
        for h in 0..<height {
            let throat = 42.0, hw: Double = Double(h) < throat ? 12+6*pow((throat-Double(h))/throat,2) : 12+2*pow((Double(h)-throat)/18,2)
            let y = base-1-h, r = Int(hw.rounded())
            fill(cx-r-2, y, 2, 1, 3); fill(cx+r+1, y, 2, 1, 3)
            // Ring beams at the lip and the throat tie the shell's two sides together.
            if h == height-1 || h == Int(throat) { fill(cx-r-2, y, 2*r+5, 1, 3) }
        }
        for k in stride(from:-16, through:16, by:4) { fill(cx+k, base-3, 1, 3, 3) }
        room(cx-11, base-height+2, cx+11, base-2, floor: base, ceiling: base-height)
    }
    /// Power house: a tall turbine hall with steel roof trusses and long windows, and the
    /// brick boiler house with four slim chimneys.
    func powerHouse(_ x: Int, base: Int) {
        let hall = 60, top = base-30
        reinforce(x-1, base-1, hall+2, 3)
        fill(x, top, 3, 30, 3); fill(x+hall-3, top, 3, 30, 3)
        for cx in stride(from:x+14, to:x+hall-6, by:14) { fill(cx, top, 2, 30, 3) }
        fill(x, top, hall, 2, 3)
        lattice(x, hall, top: top-4, base: top, rung: 4)
        for k in stride(from:x+7, to:x+hall-4, by:7) { fill(k, top-4, 1, 4, 11) }
        room(x+3, top+2, x+hall-4, base-1, floor: base, ceiling: top+1)
        for cx in stride(from:x+3, to:x+hall-4, by:14) { fill(cx, top+6, 4, base-top-6, 4); fill(cx+7, top+6, 4, base-top-6, 4) }
        let bx = x+hall+4
        house(bx, 36, 3, base: base, story: 12, pitch: 3, bay: 12)
        for k in 0..<4 { let sx = bx+4+k*8; fill(sx, 8, 2, base-8, 11); fill(sx-1, 8, 4, 1, 11) }
        target("POWER HOUSE",x,8,bx+38,base,5000)
    }
    /// Coke works: a long brick oven battery with its doors, and the coal tower on four legs
    /// fed by an inclined conveyor.
    func cokeWorks(_ x: Int, base: Int) {
        fill(x, base-14, 62, 14, 5)
        for k in stride(from:x+2, to:x+60, by:4) { fill(k, base-12, 2, 9, 11) }
        fill(x-1, base-16, 64, 2, 3)
        for k in stride(from:x+6, to:x+58, by:12) { fill(k, base-22, 3, 6, 5) }
        let tx = x+70
        for lx in [tx, tx+7, tx+14] { fill(lx, base-30, 2, 30, 3) }
        fill(tx-2, base-56, 20, 26, 3); fill(tx+1, base-53, 14, 18, 0)
        room(tx+1, base-53, tx+14, base-36, floor: base-35, ceiling: base-54)
        fill(tx+4, base-39, 8, 4, 4)
        gable(tx-3, 22, eave: base-56, 11, pitch: 3)
        for k in 0..<22 {
            let cx = tx+18+k, row = base-40+k*36/22
            fill(cx, row, 2, 2, 11)
            if k%5 == 2 || k == 21 { footTo(cx, 1, top: row+2, 11) }
        }
        target("COAL TOWER",x,base-62,tx+42,base,5000)
    }
    /// Works directorate: a four-storey brick office under a dark mansard roof, with a
    /// clock tower over the entrance.
    func directorate(_ x: Int, base: Int) {
        let eave = house(x, 52, 4, base: base, story: 9, 5, roof: 11, pitch: 3, bay: 13)
        let top = eave-26
        fill(x+21, top, 10, base-top, 5)
        fill(x+23, top+4, 6, 6, 4); fill(x+25, top+6, 2, 2, 11)
        for y in stride(from:top+14, to:eave-2, by:6) { fill(x+24, y, 4, 3, 4) }
        taper(x+20, 12, base: top, top: top-10, tip: 2, 11)
        fill(x+25, top-14, 2, 4, 11)
        target("WORKS DIRECTORATE",x-1,top-14,x+53,base,6000)
    }
}

extension World {
    // MARK: Saint Odile: the river city

    static let odileTerrain: [(x: Int, row: Int)] = [(0,93),(100,94),(400,94),(412,116),(508,116),(520,94),(1336,94)]
    func saintOdile() {
        let g = 94
        tvTower(104, base: g)
        // Terraced townhouses, narrow and tall, alternating brick and render.
        var x = 160
        for (k,(w,floors)) in [(14,4),(12,5),(16,3),(12,4),(14,5),(12,3),(16,4),(14,5)].enumerated() {
            house(x, w, floors, base: g, story: 8, k%2 == 0 ? 5 : 3, roof: k%3 == 0 ? 11 : 5, pitch: 1, bay: 20)
            x += w+3
        }
        stadium(312, base: g)
        archBridge()
        cathedral(530, base: g)
        opera(648, base: g)
        glassTower(762, base: g, floors: 12, name: "ODILE TRADE TOWER")
        glassTower(800, base: g, floors: 8, name: nil)
        glassTower(838, base: g, floors: 10, name: nil)
        cityHall(890, base: g)
        metro(1000, base: g)
        gare(1094, base: g)
        grandHotel(1240, base: g)
        landmarks += [Landmark(name:"LZ / JARDIN",x:200,y:830),Landmark(name:"RUE DES TISSERANDS",x:1500,y:620),Landmark(name:"STADE",x:2700,y:600),
                      Landmark(name:"ILL RIVER",x:3700,y:900),Landmark(name:"ÎLE SAINT-ODILE",x:4500,y:300),Landmark(name:"QUARTIER D'AFFAIRES",x:6400,y:200),
                      Landmark(name:"PLACE DE L'HÔTEL DE VILLE",x:7400,y:400),Landmark(name:"GARE CENTRALE",x:9200,y:450)]
    }
    /// TV tower: a concrete shaft carrying a flared observation pod with a glazed band, an
    /// antenna mast, and the entrance pavilion at its foot.
    func tvTower(_ x: Int, base: Int) {
        let cx = x+20
        reinforce(cx-8, base-1, 18, 4)
        fill(cx-2, 22, 6, base-22, 3)
        for y in 27...38 { let w = min(24, 6+(38-y)*2); fill(cx+1-w/2, y, w, 1, 3) }
        fill(cx-10, 30, 7, 2, 4); fill(cx+5, 30, 7, 2, 4)
        taper(cx-11, 24, base: 27, top: 22, tip: 8, 3)
        fill(cx, 2, 2, 20, 11); fill(cx-2, 10, 6, 1, 11)
        fill(x, base-8, 40, 8, 3); fill(x+2, base-6, 36, 4, 4); fill(cx-2, base-8, 6, 8, 3)
        target("TV TOWER",x,2,x+40,base,2000)
    }
    /// Stade Odile: two raked concrete stands facing across the pitch, each with a
    /// cantilevered canopy and a floodlight mast.
    func stadium(_ x: Int, base: Int) {
        let w = 80
        reinforce(x-1, base-1, w+2, 3)
        for (sx,dir) in [(x,1),(x+w,-1)] {
            for k in 0..<10 {
                let width = 26-k*2
                fill(dir > 0 ? sx : sx-width, base-1-k*2, width, 2, 3)
            }
            let back = dir > 0 ? sx : sx-3
            fill(back, base-34, 3, 34, 3)
            fill(dir > 0 ? sx : sx-14, base-36, 14, 2, 3)
            let mast = dir > 0 ? sx+1 : sx-2
            fill(mast, 18, 1, base-52, 11)
            fill(mast-3, 14, 7, 4, 5); fill(mast-2, 15, 5, 2, 4)
            // Spectators on the exposed lip of every other tier.
            for k in stride(from:0, to:9, by:2) { fill(dir > 0 ? sx+24-k*2 : sx-26+k*2, base-2-k*2, 2, 1, 6) }
        }
        fill(x+28, base-1, 24, 1, 6)
        target("STADE ODILE",x,14,x+w,base,3000)
    }
    /// Pont Saint-Odile: a deck on two river piers under a steel tied arch with hangers.
    func archBridge() {
        let deck = 92, bed = 116, a = 412, b = 508
        fill(396, deck, 128, 2, 12)
        footTo(396, 16, top: deck+2, 12); footTo(508, 16, top: deck+2, 12)
        reinforce(396, deck, 16, 8); reinforce(508, deck, 16, 8)
        for px in [430, 452, 474, 496] { fill(px, deck+2, 4, bed-deck-2, 12); fill(px-2, bed, 8, 3, 12); reinforce(px-2, bed-4, 8, 7) }
        let mid = Double(a+b)/2, half = Double(b-a)/2
        func arch(_ x: Int) -> Int { deck-1-Int((30*(1-pow((Double(x)+0.5-mid)/half,2))).rounded()) }
        for x in a..<b {
            let y0 = min(arch(x), x+1 < b ? arch(x+1) : arch(x)), y1 = max(arch(x), x+1 < b ? arch(x+1) : arch(x))
            fill(x, y0, 1, y1-y0+2, 11)
        }
        for x in stride(from:a+8, to:b-4, by:8) { fill(x, arch(x)+2, 1, deck-arch(x)-2, 11) }
        pools.append(Pool(x0:400,x1:520,row:97))
        target("PONT SAINT-ODILE",a,deck,b,deck+2,6000,span:bed)
    }
    /// Cathedral of Saint Odile: a twin-spired west front with a rose window and portal, the
    /// long nave with lancet windows under a steep copper roof, a crossing spire, and the apse.
    func cathedral(_ x: Int, base: Int) {
        reinforce(x-1, base-1, 104, 3)
        fill(x, 40, 30, base-40, 5)
        fill(x+11, base-14, 8, 14, 0); fill(x+12, base-17, 6, 3, 0); fill(x+13, base-18, 4, 1, 0)
        disc(Double(x)+15, 54, 5, 4)
        for y in stride(from:64, to:base-20, by:8) { fill(x+3, y, 4, 5, 4); fill(x+23, y, 4, 5, 4) }
        for (tx,tip) in [(x, 4),(x+20, 10)] {
            fill(tx, 26, 10, 14, 5); fill(tx+3, 30, 4, 7, 0)
            for k in 0..<3 { fill(tx+k*4, 24, 2, 2, 5) }
            taper(tx+1, 8, base: 24, top: tip, tip: 1, 5)
        }
        house(x+32, 60, 1, base: base, story: 32, 5, roof: 11, pitch: 1, bay: 10)
        fill(x+58, 30, 8, base-30, 5); fill(x+60, 34, 4, 8, 4)
        taper(x+58, 8, base: 30, top: 8, tip: 1, 11)
        house(x+92, 10, 1, base: base, story: 22, 5, roof: 11, pitch: 1)
        target("SAINT ODILE CATHEDRAL",x,4,x+102,base,6000)
    }
    /// Opera house: a colonnaded front under a pediment, a high drum and a copper dome
    /// crowned by a lantern and a statue.
    func opera(_ x: Int, base: Int) {
        let w = 90
        reinforce(x-1, base-1, w+2, 3)
        colonnade(x, w, base: base, h: 20, every: 6)
        room(x+2, base-18, x+w-3, base-1, floor: base, ceiling: base-19)
        let eave = house(x, w, 2, base: base-20, story: 10, 3, pitch: 4, bay: 15)
        let dx = x+w/2-12
        fill(dx, 30, 24, base-30, 3)
        for k in 0..<4 { fill(dx+2+k*6, 34, 3, 10, 4) }
        dome(Double(dx)+12, base: 30, 13, 11, thick: 2)
        fill(dx+9, 14, 6, 4, 3); fill(dx+10, 15, 4, 2, 4); fill(dx+11, 9, 2, 5, 11)
        _ = eave
        target("OPÉRA",x,9,x+w,base,4000)
    }
    /// Glass office tower: a concrete core, cantilevered floor slabs, and a curtain wall of
    /// glass between them. Returns nothing; with a name it becomes an objective.
    func glassTower(_ x: Int, base: Int, floors: Int, name: String?) {
        let w = 30, story = 7, roof = base-2-floors*story
        reinforce(x-1, base-1, w+2, 4)
        fill(x+11, roof, 8, base-roof, 3); fill(x, roof, 2, base-roof, 3); fill(x+w-2, roof, 2, base-roof, 3)
        for f in 0...floors { fill(x, base-2-f*story, w, 2, 3) }
        for f in 0..<floors {
            let floor = base-2-f*story
            fill(x+2, floor-story+2, 9, story-2, 4); fill(x+19, floor-story+2, 9, story-2, 4)
        }
        fill(x+9, roof-6, 12, 6, 3); fill(x+14, roof-16, 2, 10, 11)
        if let name { target(name,x,roof-16,x+w,base,5000) }
    }
    /// Hôtel de Ville: a three-storey civic block over an arcade, and its clock tower with
    /// a clock face, an open belfry and a pinnacled pyramid roof.
    func cityHall(_ x: Int, base: Int) {
        let w = 84
        reinforce(x-1, base-1, w+2, 3)
        colonnade(x, w, base: base, h: 12, every: 8, 5)
        room(x+2, base-10, x+w-3, base-1, floor: base, ceiling: base-11)
        house(x, w, 3, base: base-12, story: 9, 5, roof: 11, pitch: 2, bay: 14)
        let tx = x+36, top = 16
        fill(tx, top, 12, base-top, 5)
        disc(Double(tx)+6, Double(top)+8, 3.5, 4); fill(tx+5, top+6, 2, 3, 11)
        fill(tx+3, top+15, 6, 6, 0)
        for y in stride(from:top+26, to:base-20, by:10) { fill(tx+4, y, 4, 5, 4) }
        taper(tx-1, 14, base: top, top: top-12, tip: 2, 11)
        fill(tx-1, top-3, 2, 3, 5); fill(tx+11, top-3, 2, 3, 5)
        fill(tx+5, top-16, 2, 4, 11)
        target("HÔTEL DE VILLE",x,top-16,x+w,base,5000)
    }
    /// Metro station: a glass-and-iron entrance pavilion over an underground hall with its
    /// platform and a train standing at it. The hall's roof is road slab, so troops walk over it.
    func metro(_ x: Int, base: Int) {
        let w = 80, floor = base+18
        fill(x, base, w, floor-base, 0)
        fill(x-2, base+3, 2, floor-base-1, 3); fill(x+w, base+3, 2, floor-base-1, 3)
        fill(x-2, base, w+4, 3, 12)
        fill(x-2, floor, w+4, 2, 3)
        for cx in [x+26, x+53] { fill(cx, base+3, 2, floor-base-3, 3) }
        room(x, base+3, x+w-1, floor-1, floor: floor, ceiling: base+2)
        fill(x, floor-3, w, 3, 3)
        // A train at the platform, one car in each bay between the columns.
        for cx in [x+2, x+29, x+56] { fill(cx, floor-11, 22, 8, 11); fill(cx+2, floor-9, 18, 3, 4) }
        let px = x+30
        fill(px, base-14, 1, 14, 11); fill(px+19, base-14, 1, 14, 11)
        fill(px-2, base-15, 24, 1, 11); fill(px+1, base-13, 18, 2, 4)
        gable(px-2, 24, eave: base-15, 11, pitch: 3)
        fill(px+8, base-22, 4, 3, 5)
        target("MÉTRO ODILE",x-2,base-24,x+w+2,floor+2,4500)
    }
    /// Gare Centrale: the brick head building with a great arched window and clock, and the
    /// train shed's iron columns and glazed roof over a waiting train.
    func gare(_ x: Int, base: Int) {
        reinforce(x-1, base-1, 34, 3)
        fill(x, base-44, 32, 44, 3)
        disc(Double(x)+16, Double(base)-28, 10, 4, upper: true); fill(x+6, base-28, 20, 26, 4); fill(x+15, base-38, 2, 38, 3)
        fill(x+13, base-50, 6, 6, 5); disc(Double(x)+16, Double(base)-47, 2.5, 4)
        gable(x-1, 34, eave: base-44, 5, pitch: 2)
        let sx = x+34, sw = 100
        for cx in stride(from:sx, through:sx+sw-2, by:10) { fill(cx, base-30, 2, 30, 11) }
        // Roof girder: a solid bottom chord, truss posts, and a top chord.
        fill(sx, base-32, sw, 2, 11); fill(sx, base-35, sw, 1, 11)
        for k in stride(from:sx, to:sx+sw, by:5) { fill(k, base-34, 1, 2, 11) }
        gable(sx-1, sw+2, eave: base-35, 11, pitch: 6, attic: true)
        for cx in stride(from:sx+2, through:sx+sw-10, by:10) { fill(cx+1, base-6, 6, 4, 11); fill(cx+2, base-5, 4, 2, 4); fill(cx, base-2, 8, 2, 3) }
        target("GARE CENTRALE",x,base-50,sx+sw,base,5500)
    }
    /// Grand Hôtel: six storeys under a dark mansard roof, with domed corner turrets.
    func grandHotel(_ x: Int, base: Int) {
        let w = 80
        let eave = house(x, w, 6, base: base, story: 8, 3, roof: 11, pitch: 3, bay: 13)
        for tx in [x, x+w-10] {
            fill(tx, eave-10, 10, 10, 3); fill(tx+3, eave-8, 4, 5, 4)
            fill(tx, eave, 10, base-eave, 3)
            for y in stride(from:eave+3, to:base-4, by:8) { fill(tx+3, y, 4, 4, 4) }
            dome(Double(tx)+5, base: eave-10, 5, 11); fill(tx+4, eave-18, 2, 3, 11)
        }
        target("GRAND HÔTEL",x,eave-18,x+w,base,6500)
    }
}

extension World {
    // MARK: The Citadel: the capital's last defences

    static let citadelTerrain: [(x: Int, row: Int)] = [(0,102),(100,103),(200,103),(206,110),(224,110),(230,103),(330,103),(342,125),(438,125),(450,103),
                                                        (830,103),(860,85),(950,85),(980,103),(1290,103),(1340,80),(1584,80)]
    func citadel() {
        let g = 103
        flakTower(104, base: g)
        // Ruined outskirts: rubble heaps and a burnt-out tram.
        for (x,h) in [(160,3),(168,5),(176,2)] { taper(x, 8, base: g, top: g-h, tip: 2, 10) }
        fill(182, g-7, 16, 6, 11); fill(184, g-6, 12, 2, 4); fill(185, g-1, 3, 1, 11); fill(192, g-1, 3, 1, 11); fill(189, g-11, 1, 4, 11)
        defenceLine(232, base: g)
        kaiserBridge()
        victoryArch(470, base: g)
        // Ministry of State: a long rendered block over a colonnade.
        colonnade(532, 92, base: g, h: 12, every: 7)
        room(534, g-10, 621, g-1, floor: g, ceiling: g-11)
        fill(531, g, 94, 2, 3)
        house(532, 92, 5, base: g-12, story: 9, 3, roof: 3, pitch: 6, bay: 14)
        parliament(640, base: g)
        stateRadio(774, base: g)
        bastions()
        silos(996, base: g)
        palace(1124, base: g)
        highCommand(1344, base: 80)
        landmarks += [Landmark(name:"LZ / OUTSKIRTS",x:200,y:900),Landmark(name:"DEFENCE LINE",x:2000,y:760),Landmark(name:"SPREE",x:3100,y:1060),
                      Landmark(name:"AVENUE OF VICTORY",x:4100,y:500),Landmark(name:"PARLIAMENT",x:5500,y:150),Landmark(name:"THE CITADEL",x:7200,y:600),
                      Landmark(name:"SILO FIELD",x:8300,y:760),Landmark(name:"PALACE OF STATE",x:9600,y:300),Landmark(name:"HIGH COMMAND",x:11300,y:330)]
    }
    /// Flak tower: a windowless concrete keep with four storeys inside and gun platforms
    /// cantilevered from its top corners, each mounting a twin gun.
    func flakTower(_ x: Int, base: Int) {
        let w = 40, top = base-58
        reinforce(x-2, base-1, w+4, 4)
        fill(x, top, w, base-top, 3)
        fill(x+4, top+4, w-8, base-top-8, 0)
        room(x+4, top+4, x+w-5, base-5, floor: base-4, ceiling: top+3)
        fill(x+w/2-2, top+4, 4, base-top-8, 3)
        for f in stride(from:top+16, to:base-4, by:12) { fill(x+4, f, w-8, 2, 3); fill(x+8, f-3, 3, 3, 4); fill(x+w-11, f-3, 3, 3, 4) }
        for (px,dir) in [(x-3,-1),(x+w-9,1)] {
            fill(px, top-6, 12, 6, 3); fill(px+2, top-9, 8, 3, 3)
            for k in 0..<6 { fill(px+4+dir*k, top-10-k, 2, 1, 11) }
        }
        fill(x+16, top-4, 8, 4, 3); fill(x+19, top-12, 2, 8, 11)
        target("FLAK TOWER",x-3,top-17,x+w+3,base,2500)
    }
    /// The outer defence line: two rows of concrete dragon's teeth and two pillboxes with
    /// machine-gun slits, behind the anti-tank ditch.
    func defenceLine(_ x: Int, base: Int) {
        for row in 0..<2 { for k in 0..<7 { taper(x+row*3+k*7, 4, base: base, top: base-3-row, tip: 1, 3) } }
        for px in [x+52, x+76] {
            fill(px, base-7, 14, 7, 3); fill(px+2, base-5, 10, 3, 0); fill(px, base-4, 2, 1, 0); fill(px-4, base-4, 5, 1, 11)
            taper(px, 14, base: base-7, top: base-9, tip: 10, 3)
            fill(px+5, base-2, 4, 2, 6)
        }
        target("OUTER DEFENCE LINE",x,base-10,x+92,base,3000)
    }
    /// Kaiser bridge: stone arches on four piers, with a tall pylon carrying a bronze group at
    /// each end.
    func kaiserBridge() {
        let deck = 101, bed = 125
        fill(322, deck, 136, 2, 12)
        footTo(322, 20, top: deck+2, 12); footTo(438, 20, top: deck+2, 12)
        reinforce(322, deck, 20, 8); reinforce(438, deck, 20, 8)
        let piers = [356,378,400,422]
        for px in piers { fill(px, deck+2, 4, bed-deck-2, 12); fill(px-2, bed, 8, 3, 12); reinforce(px-2, bed-4, 8, 7) }
        let supports = [342]+piers+[438]
        for k in 0..<(supports.count-1) {
            let a = supports[k]+(k == 0 ? 0 : 4), b = supports[k+1], mid = Double(a+b)/2, half = Double(b-a)/2
            for x in a..<b { let t = abs(Double(x)+0.5-mid)/half, depth = Int((t*t*10).rounded()); if depth > 0 { fill(x, deck+2, 1, depth, 12) } }
        }
        for px in [326, 446] {
            fill(px, 62, 8, deck-62, 5); fill(px-1, 60, 10, 2, 3)
            fill(px+1, 52, 6, 8, 11); fill(px+2, 48, 4, 4, 11); fill(px+3, 45, 2, 3, 11)
        }
        for x in stride(from:344, to:436, by:4) { fill(x, deck-2, 1, 2, 11) }
        fill(344, deck-2, 89, 1, 11)
        pools.append(Pool(x0:330,x1:450,row:106))
        target("KAISER BRIDGE",342,deck,438,deck+2,6000,span:bed)
    }
    /// Victory arch: two great piers under an attic storey, the arch opening between them,
    /// and a bronze quadriga on top.
    func victoryArch(_ x: Int, base: Int) {
        let w = 52, top = 42, pier = 20
        reinforce(x-1, base-1, w+2, 4)
        fill(x, top, pier, base-top, 3); fill(x+w-pier, top, pier, base-top, 3)
        fill(x+pier, top, w-2*pier, 10, 3)
        let mid = Double(x)+Double(w)/2, half = Double(w-2*pier)/2
        for col in (x+pier)..<(x+w-pier) {
            let t = abs(Double(col)+0.5-mid)/half, drop = Int((pow(t,2)*12).rounded())
            fill(col, top+10, 1, drop, 3)
        }
        for k in 0..<2 { fill(x+5+k*(w-pier), top+14, 7, 30, 5) }
        fill(x-1, top-2, w+2, 2, 3); fill(x+2, top-5, w-4, 3, 3)
        fill(x+21, top-9, 10, 4, 11); fill(x+23, top-13, 6, 4, 11); fill(x+25, top-16, 2, 3, 11)
        target("VICTORY ARCH",x,top-16,x+w,base,4000)
    }
    /// Parliament: a domed central hall between two wings with corner towers. The dome is a
    /// steel and glass shell on a colonnaded drum, braced by ribs inside.
    func parliament(_ x: Int, base: Int) {
        let w = 120
        reinforce(x-1, base-1, w+2, 4)
        house(x+4, 34, 3, base: base, story: 10, 3, roof: 11, pitch: 4, bay: 12)
        house(x+w-38, 34, 3, base: base, story: 10, 3, roof: 11, pitch: 4, bay: 12)
        for tx in [x, x+34, x+w-38, x+w-4] { fill(tx, base-44, 4, 44, 3); taper(tx-1, 6, base: base-44, top: base-48, tip: 2, 11) }
        let dx = x+40, dw = 40, drumTop = 42
        fill(dx, drumTop, dw, base-drumTop, 3)
        fill(dx+3, drumTop+4, dw-6, 14, 0); room(dx+3, drumTop+4, dx+dw-4, drumTop+17, floor: drumTop+18, ceiling: drumTop+3)
        for k in 0..<6 { fill(dx+3+k*6, drumTop+4, 2, 14, 3) }
        colonnade(dx, dw, base: base, h: 18, every: 6)
        dome(Double(dx)+20, base: drumTop, 19, 11, thick: 2)
        for k in stride(from:-15, through:15, by:5) { let r = 19.0, h = Int((r*r-Double(k*k)).squareRoot()); fill(dx+20+k, drumTop-h+1, 1, h-1, 11) }
        fill(dx+16, drumTop-24, 1, 5, 11); fill(dx+23, drumTop-24, 1, 5, 11); fill(dx+17, drumTop-23, 6, 4, 4)
        fill(dx+16, drumTop-25, 8, 1, 11); fill(dx+19, drumTop-31, 2, 6, 11)
        target("PARLIAMENT DOME",x,drumTop-31,x+w,base,5500)
    }
    /// State radio: a tall lattice mast with service platforms and a beacon, and the brick
    /// broadcasting house at its foot.
    func stateRadio(_ x: Int, base: Int) {
        let mx = x+30
        reinforce(mx-2, base-1, 9, 4)
        lattice(mx, 5, top: 4, base: base, rung: 6)
        for y in [30, 60] { fill(mx-3, y, 11, 1, 11) }
        fill(mx+2, 0, 1, 4, 11); fill(mx+1, 1, 3, 2, 5)
        house(x, 26, 2, base: base, story: 9, 5, pitch: 2)
        fill(x+26, base-14, 4, 1, 11)
        target("STATE RADIO",x,0,mx+8,base,4500)
    }
    /// The Citadel's bastions: concrete revetments faced along both slopes of the earthwork,
    /// a parapet with embrasures, two armoured gun turrets, the powder magazine, and the flag.
    func bastions() {
        // Concrete revetments faced along the earthwork's slopes, on top of the ground.
        for x in Array(830..<860)+Array(950..<980) { fill(x, surfaceRow(x)-2, 1, 2, 3) }
        fill(860, 84, 90, 1, 3)
        for k in stride(from:862, to:948, by:6) { fill(k, 81, 3, 3, 6) }
        for tx in [870, 928] { dome(Double(tx)+5, base: 84, 6, 11); fill(tx+11, 80, 8, 1, 11); fill(tx+11, 82, 7, 1, 11) }
        fill(890, 76, 30, 8, 3); dome(905, base: 76, 10, 3); fill(898, 78, 14, 5, 0); room(898, 78, 911, 82, floor: 83, ceiling: 77)
        fill(904, 50, 1, 16, 11); fill(905, 50, 6, 4, 5)
        target("CITADEL BASTIONS",830,50,980,103,5500)
    }
    /// Missile silo field: three concrete-lined shafts with a missile standing in each under
    /// its blast door (road slab, so troops cross it), and the launch control blockhouse.
    func silos(_ x: Int, base: Int) {
        let depth = 40
        for k in 0..<3 {
            let sx = x+4+k*30
            fill(sx, base, 14, depth, 3); fill(sx+2, base, 10, depth-2, 0)
            room(sx+2, base+2, sx+11, base+depth-3, floor: base+depth-2, ceiling: base+1)
            fill(sx-2, base, 18, 2, 12)
            fill(sx+5, base+8, 4, depth-10, 11); taper(sx+5, 4, base: base+8, top: base+3, tip: 1, 11)
            fill(sx+3, base+depth-6, 2, 4, 11); fill(sx+9, base+depth-6, 2, 4, 11)
            fill(sx+6, base+14, 2, 3, 4)
        }
        fill(x+94, base-8, 22, 8, 3); fill(x+96, base-6, 18, 4, 0); room(x+96, base-6, x+113, base-3, floor: base-2, ceiling: base-7)
        fill(x+98, base-16, 1, 8, 11); fill(x+110, base-14, 1, 6, 11); fill(x+108, base-15, 5, 1, 11)
        target("MISSILE SILOS",x,base-16,x+116,base+depth,6000)
    }
    /// Palace of State: a long colonnaded façade with mansard wings and a central pavilion
    /// rising into a tower and spire.
    func palace(_ x: Int, base: Int) {
        let w = 140
        reinforce(x-1, base-1, w+2, 4)
        colonnade(x, w, base: base, h: 14, every: 7, 3)
        room(x+2, base-12, x+w-3, base-1, floor: base, ceiling: base-13)
        house(x, 56, 4, base: base-14, story: 9, 5, roof: 11, pitch: 3, bay: 14)
        house(x+w-56, 56, 4, base: base-14, story: 9, 5, roof: 11, pitch: 3, bay: 14)
        let tx = x+58, tw = 24, top = 20
        fill(tx, top, tw, base-top, 3)
        for y in stride(from:top+16, to:base-18, by:10) { fill(tx+4, y, 4, 6, 4); fill(tx+tw-8, y, 4, 6, 4) }
        disc(Double(tx)+12, Double(top)+7, 3.5, 4)
        fill(tx-2, top-2, tw+4, 2, 3)
        taper(tx+2, 20, base: top-2, top: top-12, tip: 6, 11)
        taper(tx+9, 6, base: top-12, top: top-18, tip: 1, 11)
        target("PALACE OF STATE",x,top-18,x+w,base,7000)
    }
    /// High Command: a brutalist stepped ziggurat on the hill with strip windows and a
    /// signals tower, over the deep command bunker, whose roof slab carries the hill above it.
    func highCommand(_ x: Int, base: Int) {
        var w = 150, tx = x
        for tier in 0..<5 {
            let y = base-6*(tier+1)
            fill(tx, y, w, 6, 3)
            for k in stride(from:tx+3, to:tx+w-6, by:7) { fill(k, y+2, 4, 2, 4) }
            tx += 12; w -= 24
        }
        let top = base-30
        fill(tx+10, top-24, 10, 24, 3)
        for y in stride(from:top-20, to:top-2, by:6) { fill(tx+12, y, 6, 3, 4) }
        lattice(tx+12, 5, top: top-40, base: top-24, rung: 4); fill(tx+8, top-36, 13, 1, 11)
        target("HIGH COMMAND",x,top-40,x+150,base,7000)
        // The bunker: deep under the hill, its slab roof on close-set columns.
        let b0 = base+14, b1 = base+36, bx = x+158, bw = 74
        fill(bx, b0, bw, b1-b0, 0)
        fill(bx-3, b0-3, bw+6, 3, 3); fill(bx-3, b1, bw+6, 3, 3)
        fill(bx-3, b0, 3, b1-b0, 3); fill(bx+bw, b0, 3, b1-b0, 3)
        for cx in stride(from:bx+6, to:bx+bw-2, by:8) { fill(cx, b0, 3, b1-b0, 3) }
        for cx in stride(from:bx+10, to:bx+bw-4, by:16) { fill(cx, b1-4, 4, 4, 7) }
        room(bx, b0, bx+bw-1, b1-1, floor: b1, ceiling: b0-1)
        fill(bx, b0+11, bw, 2, 3)
        target("COMMAND BUNKER",bx-3,b0-3,bx+bw+3,b1+3,8000)
    }
}
