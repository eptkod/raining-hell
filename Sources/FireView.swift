import AppKit

/// Drawing for the firebomb run and the fires it starts. Everything here is in world space
/// unless it says otherwise.
extension GameView {
    static let flameRed: UInt32 = 0xc23a18, flameOrange: UInt32 = 0xff8a2a, flameYellow: UInt32 = 0xffdc7a
    /// Soot over cells by `FireField.char` level.
    static let sootShade = [0.0,0.2,0.4,0.62]

    /// Firebombers, every fire in view, falling canisters, flying gel, and embers.
    func drawFireLayer(_ view: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let margin = view.insetBy(dx:-80,dy:-80)
        for b in world.bombers where margin.insetBy(dx:-120,dy:-60).contains(NSPoint(x:b.x,y:b.y)) {
            let ramp = b.x-b.heading*World.rampOffset
            drawTransport(x:b.x,y:b.y,heading:b.heading,open:b.released > 0 || (ramp-b.aims[0])*b.heading > -world.bombLead(b.aims[0],from:b.y)-320,firebomber:true)
        }
        drawFlames(ctx,view)
        for bomb in world.fireBombs where margin.contains(NSPoint(x:bomb.position.x,y:bomb.position.y)) { drawCanister(ctx,bomb) }
        for d in world.gelDrops where margin.contains(NSPoint(x:d.position.x,y:d.position.y)) {
            let tail = d.position+d.velocity*(-0.03)
            line([CGPoint(x:tail.x,y:tail.y),CGPoint(x:d.position.x,y:d.position.y)],Self.flameOrange,2.5,0.85)
            rect(d.position.x-1.5,d.position.y-1.5,3,3,Self.flameYellow)
        }
        for e in world.embers where margin.contains(NSPoint(x:e.position.x,y:e.position.y)) {
            rect(e.position.x-0.8,e.position.y-0.8,1.6,1.6,Self.flameYellow,min(1,e.life))
        }
    }
    /// Flames are batched into a few paths so a large fire stays cheap to draw: a soft glow
    /// over each patch of fire, a ragged sheet in every burning cell, and tongues that lick up
    /// wherever open air is above. Burning crates and sandbags glow through instead.
    func drawFlames(_ ctx: CGContext,_ view: NSRect) {
        let fire = world.fire
        guard !fire.burning.isEmpty else { return }
        let c = World.cell, cols = World.columns, t = world.elapsed, voxels = world.voxels
        let x0 = Int(view.minX/c)-2, x1 = Int(view.maxX/c)+2
        let y0 = Int((view.minY-World.top)/c)-2, y1 = Int((view.maxY-World.top)/c)+12
        var glow: [Int:Double] = [:]
        let red = CGMutablePath(), orange = CGMutablePath(), yellow = CGMutablePath(), smoulder = CGMutablePath()
        for i in fire.burning {
            let f = Double(fire.flame[i])
            guard f > 0.02 else { continue }
            let x = i%cols, y = i/cols
            guard x >= x0 && x <= x1 && y >= y0 && y <= y1 else { continue }
            let px = Double(x)*c, py = Double(y)*c+World.top
            let seed = Double((x*73+y*37)%97)
            let heat = f*(0.7+0.3*sin(t*(7+seed.truncatingRemainder(dividingBy:5))+seed))
            glow[(y/12)*10000+x/12,default:0] += f
            if voxels[i] != 0 {
                smoulder.addRect(CGRect(x:px,y:py,width:c,height:c))
                if heat > 0.55 { orange.addRect(CGRect(x:px+c*0.25,y:py+c*0.25,width:c*0.5,height:c*0.5)) }
            } else {
                let h = c*min(1,0.35+heat)
                (heat > 0.8 ? yellow : heat > 0.45 ? orange : red).addRect(CGRect(x:px,y:py+c-h,width:c,height:h))
            }
            if y > 0 && voxels[i-cols] == 0 && fire.flame[i-cols] <= 0.02 {
                let tall = c*(0.8+3.2*heat)
                orange.addRect(CGRect(x:px,y:py-tall,width:c,height:tall))
                red.addRect(CGRect(x:px+c*0.25,y:py-tall-c*0.6*heat,width:c*0.5,height:c*0.6*heat))
                yellow.addRect(CGRect(x:px+c*0.2,y:py-tall*0.45,width:c*0.6,height:tall*0.45))
            }
        }
        // Firelight: a soft radial glow over each 12-cell patch, brighter the more is burning.
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        let space = CGColorSpaceCreateDeviceRGB()
        for (k,sum) in glow {
            let gx = (Double(k%10000)*12+6)*c, gy = (Double(k/10000)*12+6)*c+World.top
            let strength = min(0.3,0.04+sum*0.008), radius = 40+min(30,sum*0.6)
            guard let gradient = CGGradient(colorSpace:space,colorComponents:[1,0.48,0.16,strength,1,0.48,0.16,0],locations:[0,1],count:2) else { continue }
            ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:gx,y:gy),startRadius:0,endCenter:CGPoint(x:gx,y:gy),endRadius:radius,options:[])
        }
        ctx.restoreGState()
        for (path,hex,alpha) in [(red,Self.flameRed,0.85),(orange,Self.flameOrange,0.9),(yellow,Self.flameYellow,0.95),(smoulder,UInt32(0xff6a20),0.5)] where !path.isEmpty {
            ctx.addPath(path); ctx.setFillColor(color(hex,alpha).cgColor); ctx.fillPath()
        }
    }
    /// A finned napalm canister, nose along its flight path.
    func drawCanister(_ ctx: CGContext,_ bomb: FireBomb) {
        ctx.saveGState()
        ctx.translateBy(x:bomb.position.x,y:bomb.position.y); ctx.rotate(by:atan2(bomb.velocity.y,bomb.velocity.x))
        func shape(_ points: [(Double,Double)],_ c: UInt32) { polygon(points.map{CGPoint(x:$0.0,y:$0.1)},c) }
        shape([(-7,-2.2),(4,-2.2),(7,-1),(7,1),(4,2.2),(-7,2.2)],0x4f5444)
        rect(-7,-2.2,11,1,0x6b705c)
        shape([(-6,-2.2),(-10,-4.8),(-9,-2.2)],0x34382e); shape([(-6,2.2),(-10,4.8),(-9,2.2)],0x34382e)
        rect(-1,-2.2,1.2,4.4,0xd2552a)
        ctx.restoreGState()
    }
    /// Preview of a firebomb run at the pointer: the C-130's run-in line, each canister's
    /// fall, and the burning pool it will leave.
    func drawFirebombGhost(_ offer: SupportOffer,at x: Double) {
        let h = world.approach(toward:x), c = World.cell, o = Self.flameOrange
        let aims = h > 0 ? World.firebombAims(x) : World.firebombAims(x).reversed()
        let refused = world.refusal(offer) != nil
        let alt = world.transportAltitude
        let start = aims[0]-h*world.bombLead(aims[0],from:alt), end = aims.last!-h*world.bombLead(aims.last!,from:alt)
        line([CGPoint(x:start-260*h,y:alt),CGPoint(x:end+60*h,y:alt)],o,1/zoom,0.3)
        polygon([CGPoint(x:end+60*h,y:alt),CGPoint(x:end+52*h,y:alt-4),CGPoint(x:end+52*h,y:alt+4)],o,0.35)
        for aim in aims {
            let path = world.trajectory(from:Vec(x:aim-h*world.bombLead(aim,from:alt),y:alt+14),velocity:World.firebombRelease(h))
            for i in stride(from:0,to:path.count-1,by:3) {
                line([CGPoint(x:path[i].x,y:path[i].y),CGPoint(x:path[i+1].x,y:path[i+1].y)],o,1.2/zoom,0.35)
            }
            guard let hit = path.last else { continue }
            let reach = Double(World.gelPoolReach)*c
            line([CGPoint(x:hit.x-reach,y:hit.y),CGPoint(x:hit.x+reach,y:hit.y)],refused ? Tac.red : o,2.5/zoom,0.75)
            polygon([CGPoint(x:hit.x-4,y:hit.y-2),CGPoint(x:hit.x,y:hit.y-12),CGPoint(x:hit.x+4,y:hit.y-2)],refused ? Tac.red : o,0.6)
        }
        if refused {
            let g = world.ground(at:x)
            line([CGPoint(x:x-6,y:g-36),CGPoint(x:x+6,y:g-24)],Tac.red,2); line([CGPoint(x:x+6,y:g-36),CGPoint(x:x-6,y:g-24)],Tac.red,2)
        }
    }
    /// Fires and firebombers on the minimap.
    func drawFireMinimap(left: Double, top: Double, sx: Double, sy: Double) {
        let fire = world.fire
        var seen = Set<Int>()
        for i in fire.burning where fire.flame[i] > 0.1 {
            let mx = Int(Double(i%World.columns)*World.cell*sx), my = Int(Double(i/World.columns)*World.cell*sy)
            if seen.insert(my*4096+mx).inserted { rect(left+Double(mx)-1,top+Double(my)-1,2,2,Self.flameOrange,0.9) }
        }
        for b in world.bombers where b.x > 0 && b.x < World.width {
            let px = left+b.x*sx, py = top+max(0,b.y-World.top)*sy, h = b.heading
            polygon([CGPoint(x:px+4*h,y:py),CGPoint(x:px-3*h,y:py-3),CGPoint(x:px-3*h,y:py+3)],Self.flameOrange)
        }
    }
    /// Screen-space labels over each firebomber.
    func drawBomberTags() {
        for b in world.bombers {
            let p = toScreen(Vec(x:b.x,y:b.y-60))
            guard p.x > -60 && p.x < 1500 && p.y > 110 && p.y < 775 else { continue }
            text(b.done ? "FIRE BOMBER · RTB" : "FIRE BOMBER",p.x-34,p.y-14,9,Self.flameOrange,.bold,true)
        }
    }
}
