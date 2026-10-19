import Foundation

// Building blocks for the later fronts' landmarks. Everything is in design units (laid
// while `unit` is `World.scale`). Each shape is made so the structure solver holds it up
// on its own: rows only narrow upward, spans stay inside each material's reach, and glass
// always hangs from a frame.
extension World {
    /// Pitched roof over x..<x+w whose lowest row sits on row `eave`-1, stepping `pitch`
    /// columns in per row up to the ridge. With `attic`, the roof is a shell over an attic
    /// room, which keeps a wide roof light enough for the walls under it.
    func gable(_ x: Int, _ w: Int, eave: Int, _ m: UInt8 = 5, pitch: Int = 1, attic: Bool = false) {
        let band = pitch+1
        var k = 0
        while w-2*k*pitch > 0 {
            let row = eave-1-k, x0 = x+k*pitch, ww = w-2*k*pitch
            if attic && ww > 2*band+2 && k > 0 {
                fill(x0, row, band, 1, m); fill(x0+ww-band, row, band, 1, m)
                room(x0+band, row, x0+ww-band-1, row, floor: eave, ceiling: row-1)
            } else { fill(x0, row, ww, 1, m) }
            k += 1
        }
        // Attic posts carry the shell, so its overhang never builds up toward the ridge.
        guard attic else { return }
        for px in stride(from:x+band+2, to:x+w-band-2, by:4) {
            var row = eave-2
            while row > 0 && material(px*unit,row*unit) == 0 { fill(px, row, 1, 1, m); row -= 1 }
        }
    }
    /// A solid taper centred on x..<x+w: `w` wide on row `base`-1, narrowing to `tip` wide
    /// on row `top`.
    func taper(_ x: Int, _ w: Int, base: Int, top: Int, tip: Int = 1, _ m: UInt8) {
        let rows = max(1,base-1-top)
        for y in top..<base {
            let t = Double(base-1-y)/Double(rows)
            var ww = Int((Double(w)+(Double(tip)-Double(w))*t).rounded())
            if (w-ww)%2 != 0 { ww += 1 }
            ww = min(w,max(tip,ww))
            fill(x+(w-ww)/2, y, ww, 1, m)
        }
    }
    /// Filled disc of radius `r` about (cx, cy); with `upper`, only its top half.
    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ m: UInt8, upper: Bool = false) {
        for y in Int(cy-r)...Int(cy+r) where !upper || Double(y) <= cy {
            for x in Int(cx-r)...Int(cx+r) where pow(Double(x)+0.5-cx,2)+pow(Double(y)+0.5-cy,2) <= r*r { fill(x, y, 1, 1, m) }
        }
    }
    /// Dome of radius `r` on row `base`, a shell `thick` cells deep (solid when 0), with
    /// its inside drawn as a room.
    func dome(_ cx: Double, base: Int, _ r: Double, _ m: UInt8, thick: Double = 0) {
        disc(cx, Double(base), r, m, upper: true)
        if thick > 0 {
            for y in Int(Double(base)-r+thick)..<base {
                for x in Int(cx-r)...Int(cx+r) where pow(Double(x)+0.5-cx,2)+pow(Double(y)+0.5-Double(base),2) < pow(r-thick,2) { fill(x, y, 1, 1, 0) }
            }
        }
    }
    /// Steel lattice mast: two legs `w` apart from row `top` down to `base`, braced by rungs
    /// every `rung` rows.
    func lattice(_ x: Int, _ w: Int, top: Int, base: Int, rung: Int = 4) {
        fill(x, top, 1, base-top, 11); fill(x+w-1, top, 1, base-top, 11)
        for y in stride(from:top, to:base, by:rung) { fill(x, y, w, 1, 11) }
    }
    /// Fills each column of x..<x+w from row `top` down to the ground with `m`, so a pier
    /// or abutment follows the terrain under it.
    func footTo(_ x: Int, _ w: Int, top: Int, _ m: UInt8) {
        for col in x..<(x+w) {
            var y = top
            while y < Self.rows/unit && !(material(col*unit,y*unit) == 1 || material(col*unit,y*unit) == 2) { fill(col, y, 1, 1, m); y += 1 }
        }
    }
    /// Brick house of `floors` storeys on ground row `base`: brick walls two cells thick,
    /// concrete floor slabs, a brick cross wall every `bay` columns, a window in each room,
    /// and a pitched roof. Returns the eave row.
    @discardableResult func house(_ x: Int, _ w: Int, _ floors: Int, base: Int, story: Int = 8, _ m: UInt8 = 5, roof: UInt8? = nil, pitch: Int = 1, bay: Int = 14, panes: Bool = true) -> Int {
        let eave = base-2-floors*story
        reinforce(x-1, base-1, w+2, 3)
        for f in 0...floors { fill(x, base-2-f*story, w, 2, 3) }
        fill(x, eave, 2, base-eave, m); fill(x+w-2, eave, 2, base-eave, m)
        let bays = max(1,Int((Double(w-4)/Double(bay)).rounded(.up)))
        var walls = [x+2]
        for b in 1..<max(2,bays) where b < bays {
            let cx = x+2+(w-4)*b/bays-1
            fill(cx, eave, 2, base-eave, m); walls.append(cx+2)
        }
        for f in 0..<floors {
            let floor = base-2-f*story
            room(x+2, floor-story+2, x+w-3, floor-1, floor: floor, ceiling: floor-story+1)
            if panes { for e in walls { fill(e, floor-story+3, 3, story-5, 4) } }
        }
        gable(x-1, w+2, eave: eave, roof ?? m, pitch: pitch, attic: true)
        return eave
    }
    /// A run of columns `every` apart under a two-row entablature, x..<x+w, standing on
    /// row `base` and `h` rows tall.
    func colonnade(_ x: Int, _ w: Int, base: Int, h: Int, every: Int = 6, _ m: UInt8 = 3) {
        fill(x, base-h, w, 2, m)
        var cx = x
        while cx+2 <= x+w { fill(cx, base-h+2, 2, h-2, m); cx += every }
        fill(x+w-2, base-h+2, 2, h-2, m)
    }
    /// Upright cylindrical tank seen side on: steel walls, a shallow domed roof carried by
    /// interior posts, and a room behind, standing on row `base`.
    func tank(_ x: Int, _ w: Int, _ h: Int, base: Int) {
        let top = base-h
        fill(x, top, 1, h, 11); fill(x+w-1, top, 1, h, 11)
        for px in stride(from:x+8, to:x+w-4, by:8) { fill(px, top, 1, h, 11) }
        for y in stride(from:top+6, to:base-2, by:6) { fill(x, y, w, 1, 11) }
        fill(x, top, w, 1, 11)
        taper(x+1, w-2, base: top, top: top-2, tip: w-8, 11)
        room(x+1, top+1, x+w-2, base-1, floor: base, ceiling: top)
    }
}
