import AppKit

/// Drawing for the water simulation (`Sources/Water.swift`). Everything here is in world space.
extension GameView {
    static let waterBody: UInt32 = 0x2c5560, waterDeep: UInt32 = 0x0e2630, waterShine: UInt32 = 0x9fc4c0
    static let waterFall: UInt32 = 0x86b8bf, waterFoam: UInt32 = 0xe9f5f3, waterChurn: UInt32 = 0x6d9ea4
    /// Darkening over damp cells by `WaterField.wet` level.
    static let wetShade = [0.0,0.1,0.18,0.26,0.34]

    /// Every body of water in view. Still water is a translucent body that darkens with depth
    /// under a shimmering surface line. Water that is moving shows it: falling water narrows
    /// into a streaked sheet, fast currents carry bands that run the way the water is going,
    /// and wherever it is churning (where a fall lands, or a flood front breaks) it foams white.
    /// Cells are batched into a few paths so a flood stays cheap to draw.
    func drawWater(_ ctx: CGContext,_ view: NSRect) {
        let water = world.water
        let c = World.cell, cols = World.columns, rows = World.rows, t = world.elapsed
        let voxels = world.voxels, mass = water.mass, vx = water.vx, vy = water.vy
        let x0 = max(0,Int(view.minX/c)-1), x1 = min(cols-1,Int(view.maxX/c)+1)
        let y0 = max(0,Int((view.minY-World.top)/c)-1), y1 = min(rows-1,Int((view.maxY-World.top)/c)+1)
        guard x0 <= x1 && y0 <= y1 else { return }
        let body = CGMutablePath(), deep = CGMutablePath(), deeper = CGMutablePath(), shine = CGMutablePath(), glint = CGMutablePath()
        let fall = CGMutablePath(), foam = CGMutablePath(), streak = CGMutablePath(), churn = CGMutablePath()
        func fract(_ v: Double) -> Double { v-floor(v) }
        func noise(_ x: Int,_ y: Int,_ k: Int) -> Double { Double(((x &* 73856093) ^ (y &* 19349663) ^ (k &* 83492791)) & 1023)/1023 }
        let flicker = Int(t*14)
        for x in x0...x1 {
            let px = Double(x)*c
            var y = y0
            // Rows of water above the first visible row still count toward depth.
            var depth = 0
            var k = y0-1
            while k >= 0 && voxels[k*cols+x] == 0 && mass[k*cols+x] > 0.5 && depth < 12 { depth += 1; k -= 1 }
            while y <= y1 {
                let i = y*cols+x
                let m = mass[i]
                guard voxels[i] == 0, m > 0.01 else { depth = 0; y += 1; continue }
                let py = Double(y)*c+World.top
                let below = y+1 < rows ? y*cols+cols+x : -1
                let falling = below >= 0 && voxels[below] == 0 && mass[below] < 0.9 && m < 0.95
                let speed = Double(abs(vx[i])+abs(vy[i]))
                if falling {
                    // A sheet of falling water, narrower the thinner it is, streaked as it drops.
                    let w = c*min(1,max(0.3,Double(m)*1.8)), off = (c-w)*(0.5+0.35*sin(t*9+Double(x)*1.7))
                    fall.addRect(CGRect(x:px+off,y:py,width:w,height:c))
                    if fract((py-t*230)/13+Double(x)*0.37) < 0.32 { streak.addRect(CGRect(x:px+off,y:py,width:w,height:c*0.6)) }
                    if speed > 0.05 && noise(x,y,flicker) < min(0.6,speed*3) { foam.addRect(CGRect(x:px+off,y:py,width:w,height:c*0.5)) }
                    depth = 0; y += 1; continue
                }
                let exposed = y == 0 || (voxels[i-cols] == 0 && mass[i-cols] < 0.05)
                var top = py, height = c
                if exposed {
                    // The surface sits at the cell's fill line and rocks with a slow swell.
                    let fill = min(1,Double(m))
                    let swell = 0.45*sin(t*2.1+Double(x)*0.31)+0.25*sin(t*3.3-Double(x)*0.83)
                    top = py+(1-fill)*c+(fill > 0.6 ? swell : 0); height = py+c-top
                    let bright = 0.5+0.5*sin(t*2+Double(x/World.scale)*0.7)
                    (bright > 0.55 ? glint : shine).addRect(CGRect(x:px,y:top,width:c,height:min(height,1.6)))
                }
                body.addRect(CGRect(x:px,y:top,width:c,height:height))
                if depth >= 4 { (depth >= 10 ? deeper : deep).addRect(CGRect(x:px,y:py,width:c,height:c)) }
                // Currents: churning water lightens and foams, and fast water carries bands
                // that run with the flow so a flood visibly rushes rather than just appearing.
                if speed > 0.03 {
                    let s = min(1,speed*6)
                    if depth < 10 && noise(x,y,flicker) < s*0.8 { churn.addRect(CGRect(x:px,y:top,width:c,height:height)) }
                    let ax = Double(abs(vx[i])), dir: Double = vx[i] >= 0 ? 1 : -1
                    if ax > 0.015 {
                        let phase = fract((px-dir*t*(60+600*min(0.25,ax)))/(18+Double(y%3)*5)+Double(y)*0.21)
                        if phase < (depth < 6 ? 0.22 : 0.12) { streak.addRect(CGRect(x:px,y:top+height*0.3,width:c,height:max(0.8,height*0.3))) }
                    }
                    if (exposed || depth < 2) && noise(x,y,flicker+7) < s*0.9 {
                        let f = c*(0.4+0.6*noise(x,y,flicker+3))
                        foam.addRect(CGRect(x:px+(c-f)/2,y:top-(exposed ? c*0.25*s : 0),width:f,height:f*0.8))
                    }
                }
                // Where a fall lands it boils white.
                if y > 0 && voxels[i-cols] == 0 && mass[i-cols] > 0.01 && mass[i-cols] < 0.95 && Double(vy[i-cols]) > 0.02 && noise(x,y,flicker+11) < 0.7 {
                    foam.addRect(CGRect(x:px-c*0.3,y:top-c*0.5,width:c*1.6,height:c))
                }
                depth = m > 0.5 ? depth+1 : 0
                y += 1
            }
        }
        for (path,hex,alpha) in [(body,Self.waterBody,0.62),(deep,Self.waterDeep,0.28),(deeper,Self.waterDeep,0.48),(churn,Self.waterChurn,0.32),
                                 (fall,Self.waterFall,0.72),(streak,UInt32(0xd2ebee),0.42),(shine,Self.waterShine,0.38),(glint,UInt32(0xc9e6e2),0.6),
                                 (foam,Self.waterFoam,0.78)] where !path.isEmpty {
            ctx.addPath(path); ctx.setFillColor(color(hex,alpha).cgColor); ctx.fillPath()
        }
        drawWaterDrops(ctx,view)
    }
    /// Spray thrown by a blast: each gout is a streak along its flight with a bright head.
    func drawWaterDrops(_ ctx: CGContext,_ view: NSRect) {
        let margin = view.insetBy(dx:-40,dy:-40)
        let streaks = CGMutablePath(), heads = CGMutablePath()
        for d in world.water.drops where margin.contains(NSPoint(x:d.position.x,y:d.position.y)) {
            let tail = d.position+d.velocity*(-0.022)
            streaks.move(to:CGPoint(x:tail.x,y:tail.y)); streaks.addLine(to:CGPoint(x:d.position.x,y:d.position.y))
            let r = min(2.2,0.9+Double(d.mass)*3)
            heads.addRect(CGRect(x:d.position.x-r/2,y:d.position.y-r/2,width:r,height:r))
        }
        guard !streaks.isEmpty else { return }
        ctx.saveGState()
        ctx.addPath(streaks); ctx.setStrokeColor(color(0xa9d2d8,0.7).cgColor); ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.strokePath()
        ctx.addPath(heads); ctx.setFillColor(color(Self.waterFoam,0.9).cgColor); ctx.fillPath()
        ctx.restoreGState()
    }
}
