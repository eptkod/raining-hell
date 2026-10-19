import AppKit

func color(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(calibratedRed:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,alpha:alpha)
}
final class GameView: NSView {
    let world = World()
    let sound = GameAudio()
    var timer: Timer?
    var previous = ProcessInfo.processInfo.systemUptime
    var pointer = Vec(x:720,y:450)
    var isHovering = false
    var tracking: NSTrackingArea?
    var help = true
    var inMenu = true
    var escMenu = false
    var pausedBeforeEscMenu = false
    /// Pause menu pages: the short main list, settings, and the exit confirmation pop-up.
    enum EscPage { case main, settings, exit }
    var escPage = EscPage.main
    /// Main pause menu rows. Sound and display live on the settings page; leaving asks first.
    let escOptions = [("RESUME","BACK TO THE FIELD"),("RESTART MAP","START THE OPERATION OVER"),
                      ("SETTINGS","SOUND, DISPLAY AND CONTROLS"),("EXIT","MAIN MENU OR QUIT GAME")]
    /// Pause menu hotkeys, in row order.
    let escKeys = ["[ESC]","[R]","[S]","[Q]"]
    /// The HVT list under the minimap starts collapsed to its header.
    var showTargets = false
    /// The status line shows as a toast that fades a few seconds after it last changed.
    var shownStatus = "", statusSince = 0.0
    var debrief = false
    /// Requisition popup, its open tab, and the offer being placed on the map.
    var deployMenu = false
    enum RequisitionTab { case troops, support }
    var deployTab = RequisitionTab.troops
    /// Troops land in the deployment zone; support can be called in anywhere on the map.
    enum Placement: Equatable { case troops(Int), support(Int) }
    /// Leaving support placement drops any Q/E side choice back to the nearer edge.
    var placing: Placement? { didSet { if !placingSupport { world.supportSide = nil } } }
    var placingName: String? {
        switch placing {
        case .troops(let i): return World.offers[i].name
        case .support(let i): return World.support[i].name
        case nil: return nil
        }
    }
    let deployFrame = NSRect(x:30,y:364,width:460,height:406)
    func deployTabRect(_ tab: RequisitionTab) -> NSRect { NSRect(x:tab == .troops ? 42 : 262,y:deployFrame.minY+28,width:216,height:24) }
    func deployRow(_ i:Int) -> NSRect { NSRect(x:42,y:deployFrame.minY+100+Double(i)*62,width:436,height:56) }
    let debriefOptions = [("MAIN MENU","ENTER · RETURN TO LEVEL SELECT"),("KEEP FIGHTING","ESC · RESUME FOR A HIGHER SCORE")]
    let levels = LevelSpec.all
    /// When the current operation was started from the lobby, for its title card.
    var briefingSince = -100.0
    /// Operation unlocked by the extraction now being debriefed, if any.
    var unlockedNow: Int?
    /// Credits the lobby will take out of the bank for the next operation, before the transfer loss.
    var withdrawal = 0
    static let withdrawalStep = 500
    /// Unlabelled cheat box in the lobby's bottom-left corner. Typing "dev" (any case) into it
    /// turns on dev mode: infinite credits now, every level open once there is more than one.
    var cheatOpen = false
    var cheatEntry = ""
    var devMode = false { didSet { world.devMode = devMode } }
    /// When dev mode was switched on, for the confirmation banner.
    var devModeSince = -100.0
    let cheatButton = NSRect(x:48,y:806,width:22,height:22)
    let cheatField = NSRect(x:76,y:806,width:150,height:22)
    /// Lobby settings: the pause menu's settings plus a danger zone for deleting saved data.
    var lobbySettings = false
    /// Settings tabs. The pause menu shows GENERAL and CONTROLS; the lobby adds the danger zone.
    enum SettingsTab { case general, controls, danger }
    var settingsTab = SettingsTab.general
    var settingsTabs: [SettingsTab] { inMenu ? [.general,.controls,.danger] : [.general,.controls] }
    /// Rebindable in-game keys, and the action on the CONTROLS tab waiting for its new key.
    let binds = Keybinds.shared
    var rebinding: KeyAction? { didSet { rebindNote = nil } }
    var rebindNote: String?
    /// The current key for `a`, as shown in hints.
    func k(_ a: KeyAction) -> String { binds.label(a) }
    /// Irreversible lobby actions. Each asks the player to type a word before it runs.
    enum DangerAction: CaseIterable {
        case deleteSave, resetSettings
        var title: String { self == .deleteSave ? "DELETE SAVE DATA" : "RESET SETTINGS" }
        var word: String { self == .deleteSave ? "DELETE" : "RESET" }
        var button: String { self == .deleteSave ? "DELETE SAVE" : "RESET" }
    }
    /// The danger action waiting on its typed confirmation, and what has been typed so far.
    var confirming: DangerAction?
    var confirmEntry = ""
    let settingsButton = NSRect(x:1144,y:38,width:28,height:28)
    /// True once the bank is loaded from and saved to disk; preview runs never touch saved data.
    var persistent = false
    /// Saves the bank between launches. Preview and screenshot runs leave it alone.
    func persistBank() {
        persistent = true
        world.bank = UserDefaults.standard.integer(forKey:"bank")
        world.onBankChange = { UserDefaults.standard.set($0,forKey:"bank") }
        world.cleared = UserDefaults.standard.integer(forKey:"cleared")
        world.onProgress = { UserDefaults.standard.set($0,forKey:"cleared") }
        binds.load()
    }
    // Camera: the world point shown at the viewport centre (720,456) and its magnification.
    var camera = Vec(x:720,y:456)
    var zoom = 1.0
    let minZoom = 0.25, maxZoom = 3.0
    var panKeys = Set<UInt16>()
    var dragAnchor: Vec?
    /// A left press on open ground: where it landed on screen and in the world. It fires on
    /// release, unless the pointer moves `boxThreshold` px first, which turns it into a
    /// selection box from `world` to the pointer.
    var press: (screen:Vec,world:Vec,boxing:Bool)?
    let boxThreshold = 6.0
    // Terrain is pre-rendered in 256 px tiles and redrawn only when a tile's cells change.
    let tileCells = 32*World.scale
    var tiles: [Int:(snapshot:[UInt8],image:CGImage)] = [:]
    /// Pre-rendered falling sections, keyed by chunk id and dropped once they land.
    var chunkImages: [Int:(image:CGImage,x0:Int,y0:Int)] = [:]
    var minimap: CGImage?
    var minimapClock = 0.0
    let minimapFrame = NSRect(x:1110,y:116,width:316,height:66)
    var scaleFactor: CGFloat { min(bounds.width/1440,bounds.height/900) }
    var offset: CGPoint { CGPoint(x:(bounds.width-1440*scaleFactor)/2,y:(bounds.height-900*scaleFactor)/2) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let palette: [UInt32] = [0x000000,0x494539,0x30393b,0x667271,0x3d6670,0x6a4536,0x72705a,0x76604a,0xffbf60,0x6f7a7d,0x59635d,0x4c5559,0x7a7564,0x6b4a36,0x6b4a36]
    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        world.onSound = { [weak self] event in
            guard let self else { return }
            // Pan with the camera and fade sounds that happen off screen.
            var heard = event
            if let x = event.x {
                let screen = self.toScreen(Vec(x:x,y:self.camera.y)).x
                heard.x = screen
                if event.cue != .order { heard.gain = max(0.15,1-max(0,abs(screen-720)-720)/1440) }
            }
            self.sound.play(heard)
        }
        world.visibility = { [weak self] p, margin in
            guard let self else { return 1 }
            let m = margin*self.zoom, s = self.toScreen(p)
            guard m > 0 else { return s.x > 0 && s.x < 1440 && s.y > 104 && s.y < 808 ? 1 : 0 }
            // Share of the event's box (2m across, centred on it) that overlaps the view.
            let w = max(0,min(s.x+m,1440)-max(s.x-m,0)), h = max(0,min(s.y+m,808)-max(s.y-m,104))
            return w*h/(4*m*m)
        }
        timer = Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.sound.sync(paused:self.world.paused || self.inMenu,active:NSApp.isActive)
            if !self.inMenu { self.world.advance(min(0.04,now-self.previous)) }
            if self.aimingRockets { self.world.faceRockets(toward:self.toWorld(self.pointer)) }
            if !self.inMenu && !self.escMenu { self.panWithKeys(min(0.04,now-self.previous)) }
            if self.steeringDrone { self.world.steerDrone(toward:self.toWorld(self.pointer)) }
            if !self.inMenu && !self.escMenu && !self.world.paused { self.followDrone(min(0.04,now-self.previous)) }
            self.previous = now
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode:.common)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow],owner:self)
        addTrackingArea(tracking!)
    }
    func rect(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ c: UInt32,_ a: Double = 1) {
        color(c,a).setFill(); NSRect(x:x,y:y,width:w,height:h).fill()
    }
    func line(_ points: [CGPoint], _ c: UInt32, _ width: Double = 1, _ a: Double = 1) {
        guard !points.isEmpty else { return }
        let p = NSBezierPath(); p.move(to:points[0]); for point in points.dropFirst() { p.line(to:point) }
        p.lineWidth = width; color(c,a).setStroke(); p.stroke()
    }
    func font(_ size: Double,_ weight: NSFont.Weight,_ mono: Bool) -> NSFont {
        mono ? NSFont.monospacedSystemFont(ofSize:size,weight:weight) : NSFont.systemFont(ofSize:size,weight:weight)
    }
    func text(_ string: String,_ x: Double,_ y: Double,_ size: Double,_ c: UInt32,_ weight: NSFont.Weight = .regular,_ mono: Bool = false,_ a: Double = 1) {
        string.draw(at:NSPoint(x:x,y:y),withAttributes:[.font:font(size,weight,mono),.foregroundColor:color(c,a)])
    }
    func textWidth(_ string: String,_ size: Double,_ weight: NSFont.Weight = .regular,_ mono: Bool = false) -> Double {
        (string as NSString).size(withAttributes:[.font:font(size,weight,mono)]).width
    }
    func polygon(_ points:[CGPoint],_ c:UInt32,_ a:Double = 1) {
        let p = NSBezierPath(); p.move(to:points[0]); for point in points.dropFirst() { p.line(to:point) }; p.close(); color(c,a).setFill(); p.fill()
    }
    func circle(_ x:Double,_ y:Double,_ radius:Double,_ c:UInt32,_ a:Double = 1) {
        color(c,a).setFill(); NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2)).fill()
    }
    // Tactical palette: night-vision olive panels, phosphor text, amber for orders.
    enum Tac {
        static let panel: UInt32 = 0x101510, raised: UInt32 = 0x1a2219, hover: UInt32 = 0x263224
        static let rule: UInt32 = 0x3a4a34, dim: UInt32 = 0x6f8263, text: UInt32 = 0xc3d1ae, bright: UInt32 = 0xe4ecd2
        static let green: UInt32 = 0x9fd88a, amber: UInt32 = 0xf0b04e, red: UInt32 = 0xe0644f, cyan: UInt32 = 0x7cc8d8
    }
    /// Points always read the same way: grouped digits and a PTS suffix, so they never
    /// look like a counter of blocks, rounds, or time.
    func pts(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return "\(f.string(from:NSNumber(value:n)) ?? "\(n)") PTS"
    }
    /// Credits, the spending currency, always carry a CR suffix so they never read as points.
    var creditsText: String { world.devMode ? "∞ CR" : cr(world.credits) }
    func cr(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return "\(f.string(from:NSNumber(value:n)) ?? "\(n)") CR"
    }
    /// Corner brackets around a frame, the signature of a targeting display.
    func brackets(_ r: NSRect,_ c: UInt32,_ length: Double = 8,_ a: Double = 1,_ width: Double = 1.5) {
        let (x0,y0,x1,y1) = (r.minX,r.minY,r.maxX,r.maxY)
        for (x,y,dx,dy) in [(x0,y0,1.0,1.0),(x1,y0,-1.0,1.0),(x0,y1,1.0,-1.0),(x1,y1,-1.0,-1.0)] {
            line([CGPoint(x:x+dx*length,y:y),CGPoint(x:x,y:y),CGPoint(x:x,y:y+dy*length)],c,width,a)
        }
    }
    /// A panel with one chamfered corner and a hairline border.
    func panel(_ r: NSRect,_ fill: UInt32,_ a: Double = 1,_ border: UInt32 = Tac.rule,_ cut: Double = 10) {
        let pts = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX-cut,y:r.minY),CGPoint(x:r.maxX,y:r.minY+cut),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY)]
        polygon(pts,fill,a); line(pts+[pts[0]],border,1)
    }
    func button(_ label:String,_ subtitle:String,_ x:Double,_ width:Double,_ accent:Bool = false,_ key:String = "") {
        let hovered = pointer.x >= x && pointer.x < x+width && pointer.y >= 827 && pointer.y < 885
        let r = NSRect(x:x,y:827,width:width,height:58)
        panel(r,accent ? (hovered ? 0x3a3018 : 0x2a2414) : (hovered ? Tac.hover : Tac.raised),1,accent ? Tac.amber : (hovered ? Tac.dim : Tac.rule))
        rect(x,827,3,58,accent ? Tac.amber : (hovered ? Tac.green : Tac.rule))
        if hovered { brackets(r.insetBy(dx:-4,dy:-4),accent ? Tac.amber : Tac.green,7) }
        text(label,x+16,836,13,accent ? Tac.amber : Tac.bright,.bold,true)
        text(subtitle,x+16,858,9,accent ? 0xa98a52 : Tac.dim,.medium,true)
        if !key.isEmpty {
            let w = max(18,textWidth(key,10,.bold,true)+12), bx = x+width-12-w
            rect(bx,835,w,16,0x000000,0.35); line([CGPoint(x:bx,y:835),CGPoint(x:bx+w,y:835),CGPoint(x:bx+w,y:851),CGPoint(x:bx,y:851),CGPoint(x:bx,y:835)],accent ? 0x8a6d3a : Tac.rule)
            text(key,bx+w/2-textWidth(key,10,.bold,true)/2,836,10,accent ? Tac.amber : Tac.text,.bold,true)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        color(0x0b141a).setFill(); bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); ctx.translateBy(x:offset.x,y:offset.y); ctx.scaleBy(x:scaleFactor,y:scaleFactor)
        ctx.setShouldAntialias(false)
        drawBattlefield(ctx)
        ctx.setShouldAntialias(true)
        if inMenu { drawMenu() } else { drawSelectionBox(); drawHUD() }
        if debrief { drawDebrief() }
        if escMenu { drawEscMenu() }
        ctx.restoreGState()
    }
    func toScreen(_ p: Vec) -> Vec { Vec(x:(p.x-camera.x)*zoom+720,y:(p.y-camera.y)*zoom+456) }
    func toWorld(_ p: Vec) -> Vec { Vec(x:(p.x-720)/zoom+camera.x,y:(p.y-456)/zoom+camera.y) }
    func clampCamera() {
        zoom = max(minZoom,min(maxZoom,zoom))
        // The view may rise into open sky above the map but never past its sides or bedrock;
        // when zoomed far out the spare height goes to sky.
        let halfW = 720/zoom, halfH = 352/zoom, minY = World.top-World.skyHeight, maxY = World.bottom
        camera.x = World.width <= halfW*2 ? World.width/2 : max(halfW,min(World.width-halfW,camera.x))
        camera.y = maxY-minY <= halfH*2 ? maxY-halfH : max(minY+halfH,min(maxY-halfH,camera.y))
    }
    func zoom(by factor: Double, at screen: Vec) {
        let anchor = toWorld(screen)
        zoom = max(minZoom,min(maxZoom,zoom*factor))
        camera = Vec(x:anchor.x-(screen.x-720)/zoom,y:anchor.y-(screen.y-456)/zoom)
        clampCamera()
    }
    /// Frames the landing zone; deeper-lying maps start the view lower to keep it in shot.
    func resetCamera() { camera = Vec(x:720,y:456+Double(World.spec.lift)*World.cell*Double(World.scale)); zoom = 1; clampCamera() }
    func panWithKeys(_ dt: Double) {
        guard !panKeys.isEmpty else { return }
        let speed = 900*dt/zoom
        if panKeys.contains(binds.key(.panLeft)) { camera.x -= speed }
        if panKeys.contains(binds.key(.panRight)) { camera.x += speed }
        if panKeys.contains(binds.key(.panUp)) { camera.y -= speed }
        if panKeys.contains(binds.key(.panDown)) { camera.y += speed }
        clampCamera()
    }
    /// Keeps a flying drone in frame. The camera only moves once the drone leaves the middle
    /// of the view, so inside that box the pointer is a fixed point on the map the drone flies
    /// to; holding the pointer near the edge of the view keeps it flying that way.
    func followDrone(_ dt: Double) {
        guard let d = world.drone else { return }
        let s = toScreen(d.position), box = NSRect(x:420,y:286,width:600,height:340)
        let sx = s.x < box.minX ? s.x-box.minX : s.x > box.maxX ? s.x-box.maxX : 0
        let sy = s.y < box.minY ? s.y-box.minY : s.y > box.maxY ? s.y-box.maxY : 0
        guard sx != 0 || sy != 0 else { return }
        let ease = min(1,dt*8)
        camera = Vec(x:camera.x+sx/zoom*ease,y:camera.y+sy/zoom*ease)
        clampCamera()
    }
    /// Whether the pointer is flying the drone: one is under control and the pointer is over
    /// the battlefield with no menu or placement in the way.
    var steeringDrone: Bool {
        world.drone?.piloted == true && isHovering && !inMenu && !escMenu && !debrief && !deployMenu && placing == nil
            && pointer.y > 104 && pointer.y < 808 && !minimapFrame.contains(NSPoint(x:pointer.x,y:pointer.y))
    }
    func focusSelection() {
        let units = world.soldiers.filter{$0.selected}.isEmpty ? world.soldiers : world.soldiers.filter{$0.selected}
        guard !units.isEmpty else { return }
        camera = Vec(x:units.map{$0.position.x}.reduce(0,+)/Double(units.count),y:units.map{$0.position.y}.reduce(0,+)/Double(units.count)-40)
        clampCamera()
    }
    /// Each operation's sky and distant country, so a front is recognisable from its first frame.
    struct Backdrop {
        var sky: (UInt32,UInt32), cloud: UInt32, moon: Double
        var far: UInt32, near: UInt32, tree: UInt32
        /// Pine crowns, if a shade apart from the trunks.
        var leaf: UInt32? = nil
        /// Height of the far hills relative to the first front's.
        var peaks = 1.0
        /// Distant rooftops and chimneys (`stacks`) behind the near hills instead of trees.
        var roofs = false, stacks = false
        /// Fires glowing low on the horizon, if any.
        var glow: UInt32? = nil
    }
    static let backdrops = [
        // Kessel Crossing: rain over teal hills.
        Backdrop(sky:(0x172a35,0x5c7372),cloud:0x899b98,moon:1,far:0x344d55,near:0x2b444a,tree:0x233b3f,leaf:0x263e42),
        // Marrow Ferry: grey dawn breaking pink over the estuary.
        Backdrop(sky:(0x2a2d3f,0x9c7f7d),cloud:0xc9a9a0,moon:0.4,far:0x4a4b5c,near:0x3a3c4b,tree:0x2e3140),
        // Irongate Pass: cold, clear air under high snow peaks.
        Backdrop(sky:(0x0f1d33,0x7d98ad),cloud:0xd6e2ea,moon:1.4,far:0x5d7286,near:0x32424f,tree:0x24323c,peaks:2.1),
        // Vestra Works: smog-brown dusk and a skyline of chimneys.
        Backdrop(sky:(0x2b2117,0xa7703c),cloud:0x7d6a52,moon:0.25,far:0x4d3d2c,near:0x3a2f24,tree:0x2c241c,stacks:true,glow:0xd8792e),
        // Saint Odile: deep night over the city's rooftops.
        Backdrop(sky:(0x070b1a,0x26355a),cloud:0x46547a,moon:1.8,far:0x18213a,near:0x121a2e,tree:0x0e1526,roofs:true),
        // The Citadel: the capital burning under a red sky.
        Backdrop(sky:(0x1a0909,0x8a2f1c),cloud:0x6e3a2c,moon:0.3,far:0x3a1c18,near:0x2a1512,tree:0x1f100e,peaks:0.7,roofs:true,stacks:true,glow:0xff6a2a)]
    func drawBackground() {
        let b = Self.backdrops[min(World.level,Self.backdrops.count-1)]
        let gradient = NSGradient(starting:color(b.sky.0),ending:color(b.sky.1))!
        gradient.draw(in:NSRect(x:0,y:104,width:1440,height:704),angle:90)
        // Distant layers drift slower than the battlefield for depth; the horizon sits at
        // the same height above the ground on every front.
        let horizon = toScreen(Vec(x:0,y:552+Double(World.spec.lift)*World.cell*Double(World.scale))).y
        let lift = (horizon-552)*0.5
        let drift = camera.x*zoom
        circle(1090-drift*0.01,216+lift*0.3,57,0xadc1b8,0.17*b.moon); circle(1090-drift*0.01,216+lift*0.3,40,0xbcd0c5,0.14*b.moon)
        // Sparse distant light and long banks of low cloud.
        for n in 0..<14 {
            let x = (Double((n*197)%1510)-drift*0.04).truncatingRemainder(dividingBy:1510)
            let y = 155+Double((n*41)%185)+lift*0.4
            for wrap in [x < 0 ? x+1510 : x, (x < 0 ? x+1510 : x)-1510] {
                rect(wrap-70,y,140+Double(n%4)*44,5,b.cloud,0.065)
                rect(wrap-40,y+6,210,2,b.cloud,0.04)
            }
        }
        if let glow = b.glow {
            NSGradient(starting:color(glow,0),ending:color(glow,0.3))!.draw(in:NSRect(x:0,y:300+lift,width:1440,height:200),angle:90)
        }
        let far: [(Double,Double)] = [(0,444),(100,350),(165,380),(320,257),(466,386),(555,340),(720,451),(848,332),(953,396),(1120,294),(1320,435),(1440,444)].map{ ($0.0,451-(451-$0.1)*b.peaks) }
        let near: [(Double,Double)] = [(0,484),(130,419),(266,462),(450,399),(620,487),(800,436),(1010,477),(1250,390),(1440,484)]
        for (ridge,shade,rate) in [(far,b.far,0.08),(near,b.near,0.16)] {
            let shift = -(drift*rate).truncatingRemainder(dividingBy:1440)
            for tile in [shift-1440,shift,shift+1440] where tile < 1440 && tile > -1440 {
                polygon(ridge.map{CGPoint(x:$0.0+tile,y:$0.1+lift)}+[CGPoint(x:1440+tile,y:2000),CGPoint(x:tile,y:2000)],shade)
            }
            // Snow on the high peaks.
            if b.peaks > 1.5 && rate < 0.1 {
                for tile in [shift-1440,shift,shift+1440] where tile < 1440 && tile > -1440 {
                    for k in 1..<ridge.count-1 where ridge[k].1 < ridge[k-1].1 && ridge[k].1 < ridge[k+1].1 && ridge[k].1 < 260 {
                        let (x,y) = (ridge[k].0+tile,ridge[k].1+lift)
                        polygon([CGPoint(x:x,y:y),CGPoint(x:x+(ridge[k+1].0-ridge[k].0)*0.22,y:y+34),CGPoint(x:x-(ridge[k].0-ridge[k-1].0)*0.22,y:y+34)],0xe4edf2,0.75)
                    }
                }
            }
        }
        let treeShift = -(drift*0.16).truncatingRemainder(dividingBy:1440)
        for n in 0..<48 {
            var x = Double((n*89)%1440)+treeShift
            if x < -30 { x += 1440 }
            let y = 476+Double((n*7)%31)+lift, h = 32+Double(n%7)*8
            if b.roofs || b.stacks {
                // Town silhouettes: blocks with the odd lit window, and works chimneys.
                if b.stacks && n%6 == 0 { rect(x+4,y-h*2.2,7,h*2.2,b.tree); continue }
                guard b.roofs else { continue }
                let w = 26+Double(n%5)*9
                rect(x-w/2,y-h,w,h+40,b.tree)
                if n%3 == 0 { rect(x-w/2+6,y-h+8,3,3,0xf2c46a,0.5) }
            } else {
                rect(x,y-h,3,h,b.tree)
                polygon([CGPoint(x:x-13,y:y-12),CGPoint(x:x+1,y:y-h),CGPoint(x:x+16,y:y-12)],b.leaf ?? b.tree)
            }
        }
    }
    // Prototype UI & graphics are subject to change.
    /// `piece` replaces the world grid for a falling section: its own cells keep their
    /// textures and edge shading, and rooms behind it are not drawn.
    func drawCells(_ x0: Int,_ y0: Int,_ x1: Int,_ y1: Int,piece: [Int:UInt8]? = nil) {
        // Patterns stay on the 8 px design grid (`u` voxels) while each voxel is `c` px.
        let c = World.cell, u = World.scale, q = c/8
        let cols = World.columns
        func material(_ x: Int,_ y: Int) -> UInt8 {
            guard let piece = piece else { return world.material(x,y) }
            return x >= 0 && x < cols ? piece[world.index(x,y)] ?? 0 : 0
        }
        func solid(_ x: Int,_ y: Int) -> Bool { let m = material(x,y); return m != 0 && m != 4 && !World.isBar(m) }
        // Fire soot darkens standing cells and rooms; falling sections keep their own look.
        let soot = piece == nil ? world.fire.char : []
        // Damp ground, rubble and walls go darker where water has touched them.
        let wet = piece == nil ? world.water.wet : []
        // Interiors: each room gets its own wallpaper, wainscot, ceiling lamps, and
        // furniture, all painted on the destructible rear panel.
        let papers: [(UInt32,UInt32)] = [(0x26332f,0x2b3934),(0x352d24,0x3c332a),(0x27303a,0x2c3641),(0x36292b,0x3d2f31),(0x2c302e,0x323735)]
        for y in max(0,y0)..<min(World.rows,y1) {
            for x in max(0,x0)..<min(World.columns,x1) where piece == nil && world.backdrops[world.index(x,y)] >= 0 {
                let i = world.index(x,y), px = Double(x)*c, py = Double(y)*c+World.top
                let id = Int(world.roomOf[i])
                let room = id >= 0 ? world.rooms[id] : CellRect(x0:x,y0:y,x1:x,y1:y)
                let lx = x-room.x0, w = room.x1-room.x0+1, h = room.y1-room.y0+1
                let above = world.backdrops[i]/cols-y, below = y-world.ceilings[i]/cols
                let lit = id >= 0 && (id*5+1)%3 != 0
                let (paper,stripe) = papers[id >= 0 ? (id*7+3)%papers.count : 4]
                rect(px,py,c,c,paper)
                if (lx/u)%3 == 0 { rect(px,py,c,c,stripe) }
                // Wainscot, dado rail, and skirting board.
                if above <= 2*u { rect(px,py,c,c,0x000000,0.2) }
                if above == 2*u { rect(px,py,c,1,0x5a5446,0.7) }
                if above == 1 { rect(px,py+c-2*q,c,2*q,0x161816) }
                // Furniture, placed per room so it reads the same across tiles.
                func slot(_ fraction: Double,_ width: Int) -> Int? {
                    let start = Int(Double(w)*fraction)
                    return lx >= start && lx < start+width ? lx-start : nil
                }
                if w >= 14*u, h >= 6*u, id%2 == 0, let d = slot(0.62,3*u), above <= 5*u {
                    // Interior door with frame and handle.
                    let edge = d == 0 || d == 3*u-1 || above == 5*u
                    rect(px,py,c,c,edge ? 0x1b1714 : 0x3a2c22)
                    if !edge && d == 3*u-2 && above == 5*u/2 { rect(px+q*2,py+q*2,c/2,c/2,0xb39a62) }
                    if !edge && (above == 2*u || above == 4*u) { rect(px,py,c,1,0x2a1f18) }
                } else if w >= 10*u, h >= 6*u, let d = slot(0.25,3*u), above > 3*u+1, above <= 5*u+1 {
                    // Framed landscape painting.
                    let edge = d == 0 || d == 3*u-1 || above == 3*u+2 || above == 5*u+1
                    rect(px,py,c,c,edge ? 0x5f4a31 : (above > 4*u+1 ? 0x56707a : 0x5a6a45))
                } else if w >= 22*u, id%3 != 1, let d = slot(0.08,3*u), above <= 4*u {
                    // Bookshelf with coloured spines.
                    let edge = d == 0 || d == 3*u-1 || above == 4*u
                    rect(px,py,c,c,0x2a2018)
                    if !edge {
                        let books: [UInt32] = [0x6a3a2e,0x3e5a4a,0x8a7442,0x3b4660,0x5c3550]
                        rect(px+q,py+2*q,c-2*q,c-2*q,books[(x*7+(above/u)*3)%books.count],0.85)
                    }
                    if above%u == 1 { rect(px,py+c-q*2,c,q*2,0x4a3826) }
                }
                if let f = world.fixtures.first(where:{ x >= $0.x && x < $0.x+$0.w && y >= $0.y && y < $0.y+$0.h }) {
                    // Notice board with pinned papers.
                    let edge = x == f.x || x == f.x+f.w-1 || y == f.y || y == f.y+f.h-1
                    rect(px,py,c,c,edge ? 0x4a3a28 : 0x6a5638)
                    if !edge && (x-f.x)%3 != 0 && (y-f.y)%3 != 0 { rect(px,py,c,c,((x-f.x)/3+(y-f.y)/3)%3 == 0 ? 0xc8b071 : 0xb9b49a) }
                }
                // Hanging ceiling lamps and their warm glow.
                let lamps = max(1,w/(16*u))
                let k = min(lamps-1,lx*lamps/max(1,w))
                let lampX = room.x0+(2*k+1)*w/(2*lamps), dx = x-lampX, lampY = y-below+u+2
                if dx == 0 && below <= u { rect(px+c/2-q,py,2*q,c,0x121414) }
                if abs(dx) <= 1 && below == u+1 { rect(px,py+(dx == 0 ? 0 : c/2),c,dx == 0 ? c : c/2,0x6d6450) }
                if dx == 0 && below == u+2 { rect(px+q,py,c-2*q,c/2,lit ? 0xf6d892 : 0x3d3a33) }
                if lit {
                    let d = hypot(Double(dx),Double(y-lampY))/Double(11*u)
                    if d < 1 { rect(px,py,c,c,0xe8ac5c,0.24*(1-d)*(1-d)) }
                } else { rect(px,py,c,c,0x000000,0.22) }
                // Ambient occlusion beneath the ceiling, above the floor, and beside walls.
                if below <= 3 { rect(px,py,c,c,0x000000,[0.34,0.2,0.09][max(0,below-1)]) }
                if above == 1 { rect(px,py,c,c,0x000000,0.15) }
                for (side,shade) in [(1,0.3),(2,0.14)] {
                    if solid(x-side,y) { rect(px,py,c,c,0x000000,shade); break }
                }
                for (side,shade) in [(1,0.24),(2,0.1)] {
                    if solid(x+side,y) { rect(px,py,c,c,0x000000,shade); break }
                }
                if soot[i] > 0 { rect(px,py,c,c,0x0e0b09,Self.sootShade[Int(min(3,soot[i]))]) }
            }
        }
        // Voxel tiles use deterministic variations, exposed rims, and material details.
        for y in max(0,y0)..<min(World.rows,y1) {
            for x in max(0,x0)..<min(World.columns,x1) {
                let m = material(x,y)
                if m == 0 { continue }
                let px = Double(x)*c, py = Double(y)*c+World.top
                let hash = (x*73+y*37+x*y*3)%17
                let i = world.index(x,y)
                switch m {
                case 3:
                    // Cast concrete: soft weathering patches, panel joints, and rain stains.
                    rect(px,py,c,c,palette[3])
                    let patch = ((x/(3*u))*31+(y/(3*u))*17+(x/(7*u))*5)%9
                    if patch < 3 { rect(px,py,c,c,0x000000,0.04+Double(patch)*0.025) }
                    if patch == 8 { rect(px,py,c,c,0xd6d2b8,0.05) }
                    if hash < 3 { rect(px,py,c,c,0x000000,0.05) }
                    if y%(4*u) == 0 { rect(px,py,c,1,0x4b5655,0.55) }
                    if x%(6*u) == 0 { rect(px,py,1,c,0x4b5655,0.4) }
                    for d in 1...7 where material(x,y-d) == 4 {
                        if (x+hash)%3 != 0 { rect(px+Double(hash%3)*q*2,py,max(1,q*2),c,0x1f2a2a,0.18*(1-Double(d)/8)) }
                        break
                    }
                    if material(x,y-1) == 4 { rect(px,py,c,2*q,0xb8c2b8); rect(px,py+2*q,c,q,0x000000,0.25) }
                case 12:
                    // Bridge concrete: warmer, coarser aggregate in large poured lifts, with a
                    // dark asphalt road surface on top and expansion joints across the deck.
                    rect(px,py,c,c,palette[12])
                    if hash < 4 { rect(px,py,c,c,0x000000,0.07) }
                    if hash > 14 { rect(px,py,c,c,0xd8cfae,0.08) }
                    if y%(6*u) == 0 { rect(px,py,c,1,0x4f4b40,0.5) }
                    if x%(12*u) == 0 { rect(px,py,max(1,q),c,0x3c3a33,0.6) }
                    if world.footings[i] { rect(px,py,c,c,0x000000,0.12) }
                case 5:
                    // Running-bond brickwork with mortar joints and soot.
                    let course = y%2, brick = (x+course)/2
                    let shades: [UInt32] = [0x6a4536,0x734b39,0x5f3f33,0x7a5240,0x5a3c30,0x6e4a3a]
                    rect(px,py,c,c,shades[(brick*7+y*13+brick*y)%shades.count])
                    rect(px,py,c,max(1,q),0x3a2c26)
                    if (x+course)%2 == 0 { rect(px,py,max(1,q),c,0x3a2c26) }
                    if hash < 4 { rect(px,py,c,c,0x000000,0.1) }
                case 11:
                    // Riveted steel plate with rust runs.
                    rect(px,py,c,c,palette[11])
                    if y%(2*u) == 0 { rect(px,py,c,1,0x343b3e) }
                    if x%(3*u) == 0 { rect(px,py,1,c,0x343b3e) }
                    if x%(3*u) == 1 && y%(2*u) == 1 { rect(px,py,max(1,q*2),max(1,q*2),0x8d989b) }
                    if (x*13+y/5)%7 == 0 { rect(px+q*2,py,max(1,q*2),c,0x7a4a2c,0.35) }
                    if hash < 4 { rect(px,py,c,c,0x000000,0.08) }
                case 4:
                    // Window glass: tinted and see-through, with frames, mullions, and reflections.
                    if world.backdrops[i] < 0 { rect(px,py,c,c,0x182629) }
                    let id = Int(world.paneOf[i])
                    let p = id >= 0 ? world.panes[id] : CellRect(x0:x,y0:y,x1:x,y1:y)
                    let t = Double(y-p.y0)/Double(max(1,p.y1-p.y0))
                    rect(px,py,c,c,0x2a515b,0.5)
                    rect(px,py,c,c,0x9fc8cc,0.2*(1-t))
                    if (x-p.x0+y-p.y0)%9 < 2 { rect(px,py,c,c,0xdff0ee,0.12) }
                    let room = world.roomOf[i]
                    if room >= 0 && (Int(room)*5+1)%3 != 0 { rect(px,py,c,c,0xf0b860,0.08) }
                    let frame: UInt32 = 0x1d2427
                    if x == p.x0 { rect(px,py,max(1,q*2),c,frame) }
                    if x == p.x1 { rect(px+c-max(1,q*2),py,max(1,q*2),c,frame) }
                    if y == p.y0 { rect(px,py,c,max(1,q*2),frame) }
                    if y == p.y1 { rect(px,py+c-max(1,q*2),c,max(1,q*2),frame) }
                    if p.x1-p.x0 >= 3 && x == (p.x0+p.x1+1)/2 { rect(px,py,max(1,q),c,frame) }
                    if p.y1-p.y0 >= 5 && y == p.y0+(p.y1-p.y0+1)/3 { rect(px,py,c,max(1,q),frame) }
                case World.barH, World.barV:
                    // Exposed rebar: a rusted ribbed bar through the middle of the cell, along
                    // the slab or up the column it was cast in.
                    let w = max(1,3*q), ribbed = (m == World.barH ? x : y)%2 == 0
                    let rust: UInt32 = hash < 6 ? 0x7a4a2c : 0x5c4334
                    if m == World.barH {
                        rect(px,py+c/2-w/2,c,w,rust); rect(px,py+c/2-w/2,c,max(1,q),0xa0765a,0.6)
                        if ribbed { rect(px+c/2-q,py+c/2-w/2-q,2*q,w+2*q,rust) }
                    } else {
                        rect(px+c/2-w/2,py,w,c,rust); rect(px+c/2-w/2,py,max(1,q),c,0xa0765a,0.6)
                        if ribbed { rect(px+c/2-w/2-q,py+c/2-q,w+2*q,2*q,rust) }
                    }
                default:
                    rect(px,py,c,c,palette[Int(m)])
                    if hash < 5 { rect(px,py,c,c,0x000000,0.09+Double(hash)*0.02) }
                    if hash > 13 { rect(px,py,c,c,0xc4bd91,0.09) }
                }
                // Bare bars are thin enough that the faces behind them still catch the light.
                func open(_ x: Int,_ y: Int) -> Bool { let n = material(x,y); return n == 0 || World.isBar(n) }
                if m == 3 || m == 5 || m == 11 || m == 12 {
                    // Light from the upper left: lit tops and left faces, shaded right faces and undersides.
                    let top: UInt32 = m == 3 ? 0xa9b4ab : (m == 5 ? 0x9a7a62 : (m == 12 ? 0x3a3a36 : 0x8c989b))
                    if open(x,y-1) { rect(px,py,c,max(1,2*q),top) }
                    if open(x-1,y) { rect(px,py,max(1,q),c,top,0.55) }
                    if open(x+1,y) { rect(px+c-max(1,q),py,max(1,q),c,0x000000,0.35) }
                    if open(x,y+1) { rect(px,py+c-max(1,q),c,max(1,q),0x000000,0.4) }
                } else if m != 4 && !World.isBar(m) && material(x,y-1) == 0 {
                    rect(px,py,c,max(1,2*q),m == 1 ? 0x92967a : (m == 2 ? 0x617175 : 0x8f9e94))
                    if m == 1 && x%u == 0 { rect(px+Double(hash%5)*q,py-2*q,max(1,2*q),3*q,0x7d9272) }
                }
                if m == 7 && (x%(5*u) == 0 || y%(4*u) == 0) { rect(px,py,c,max(1,2*q),0x9e8059) }
                if m == 6 && x%(3*u) == 0 { rect(px,py,1,c,0x474c41) }
                if m <= 2 && hash == 3 { rect(px+2*q,py+3*q,max(1,3*q),max(1,2*q),0x161e23,0.45) }
                if !soot.isEmpty && soot[i] > 0 { rect(px,py,c,c,0x0e0b09,Self.sootShade[Int(min(3,soot[i]))]) }
                if !wet.isEmpty && wet[i] > 0 {
                    rect(px,py,c,c,0x0b171c,Self.wetShade[Int(min(4,wet[i]))])
                    // A wet surface open to the sky catches a faint sheen.
                    if wet[i] >= 3 && material(x,y-1) == 0 { rect(px,py,c,max(1,q),0xa8c8c6,0.22) }
                }
            }
        }
    }
    /// A falling section is painted once with the same textures it had standing, then
    /// moved and rotated as a single image until it lands and crumbles.
    func chunkImage(_ chunk: FallingChunk) -> (CGImage,Vec)? {
        let c = World.cell
        guard let first = chunk.cells.first else { return nil }
        let offset = Vec(x:chunk.cells.map{$0.x}.min()!-c/2,y:chunk.cells.map{$0.y}.min()!-c/2)
        if let cached = chunkImages[chunk.id] { return (cached.image,offset) }
        guard first.gx >= 0 else { return nil }
        let x0 = chunk.cells.map{$0.gx}.min()!, x1 = chunk.cells.map{$0.gx}.max()!
        let y0 = chunk.cells.map{$0.gy}.min()!, y1 = chunk.cells.map{$0.gy}.max()!
        let width = (x1-x0+1)*Int(c), height = (y1-y0+1)*Int(c)
        guard let bitmap = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.setShouldAntialias(false)
        if let parent = chunkImages[chunk.parent] {
            // A piece broken off a section reuses its texture with the crumbled cells cut away.
            bitmap.interpolationQuality = .none
            bitmap.draw(parent.image,in:CGRect(x:Double(parent.x0-x0)*c,y:Double(height)-Double(parent.y0-y0)*c-Double(parent.image.height),width:Double(parent.image.width),height:Double(parent.image.height)))
            let kept = Set(chunk.cells.map{ $0.gy*World.columns+$0.gx })
            for y in y0...y1 { for x in x0...x1 where !kept.contains(y*World.columns+x) {
                bitmap.clear(CGRect(x:Double(x-x0)*c,y:Double(height)-Double(y-y0+1)*c,width:c,height:c))
            } }
        } else {
            var piece: [Int:UInt8] = [:]
            for cell in chunk.cells { piece[world.index(cell.gx,cell.gy)] = cell.material }
            bitmap.translateBy(x:0,y:CGFloat(height)); bitmap.scaleBy(x:1,y:-1)
            bitmap.translateBy(x:-CGFloat(Double(x0)*c),y:-CGFloat(Double(y0)*c+World.top))
            let screen = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext:bitmap,flipped:true)
            drawCells(x0,y0,x1+1,y1+1,piece:piece)
            NSGraphicsContext.current = screen
        }
        guard let image = bitmap.makeImage() else { return nil }
        chunkImages[chunk.id] = (image,x0,y0)
        return (image,offset)
    }
    func tile(_ tx: Int,_ ty: Int) -> CGImage? {
        let x0 = tx*tileCells, y0 = ty*tileCells
        // Snapshot the cells (plus the rims above and grass tufts below) and backdrops.
        var snapshot: [UInt8] = []
        snapshot.reserveCapacity((tileCells+2)*tileCells*2)
        // Neighbouring cells shade edges and stain walls, so include a margin around the tile.
        for y in y0-8...y0+tileCells { for x in x0-1...x0+tileCells { snapshot.append(world.material(x,y)) } }
        for y in y0..<min(World.rows,y0+tileCells) {
            for x in x0..<min(World.columns,x0+tileCells) { snapshot.append(world.backdrops[world.index(x,y)] >= 0 ? 1 : 0) }
        }
        let soot = world.fire.char, wet = world.water.wet
        for y in y0..<min(World.rows,y0+tileCells) {
            for x in x0..<min(World.columns,x0+tileCells) { snapshot.append(soot[world.index(x,y)]); snapshot.append(wet[world.index(x,y)]) }
        }
        let key = ty*1000+tx
        if let cached = tiles[key], cached.snapshot == snapshot { return cached.image }
        let size = tileCells*Int(World.cell)
        guard let bitmap = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.translateBy(x:0,y:CGFloat(size)); bitmap.scaleBy(x:1,y:-1)
        bitmap.translateBy(x:-CGFloat(Double(x0)*World.cell),y:-CGFloat(Double(y0)*World.cell+World.top))
        bitmap.setShouldAntialias(false)
        let screen = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext:bitmap,flipped:true)
        drawCells(x0,y0,x0+tileCells,y0+tileCells+1)
        NSGraphicsContext.current = screen
        guard let image = bitmap.makeImage() else { return nil }
        tiles[key] = (snapshot,image)
        return image
    }
    func drawBattlefield(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to:CGRect(x:0,y:104,width:1440,height:704))
        if world.shake > 0 { ctx.translateBy(x:sin(world.elapsed*110)*world.shake,y:cos(world.elapsed*90)*world.shake*0.4) }
        drawBackground()
        ctx.saveGState()
        ctx.translateBy(x:720,y:456); ctx.scaleBy(x:zoom,y:zoom); ctx.translateBy(x:-camera.x,y:-camera.y)
        let corner = toWorld(Vec(x:0,y:104)), far = toWorld(Vec(x:1440,y:808))
        let view = NSRect(x:corner.x,y:corner.y,width:far.x-corner.x,height:far.y-corner.y)
        rect(-200,World.bottom,World.width+400,max(0,far.y-World.bottom)+10,0x161c1f)
        ctx.interpolationQuality = .none
        let span = Double(tileCells)*World.cell
        for ty in max(0,Int((view.minY-World.top)/span))...max(0,min((World.rows-1)/tileCells,Int((view.maxY-World.top)/span))) {
            for tx in max(0,Int(view.minX/span))...min((World.columns-1)/tileCells,max(0,Int(view.maxX/span))) {
                guard let image = tile(tx,ty) else { continue }
                ctx.saveGState()
                ctx.translateBy(x:Double(tx)*span,y:Double(ty)*span+World.top+span); ctx.scaleBy(x:1,y:-1)
                ctx.draw(image,in:CGRect(x:0,y:0,width:span,height:span))
                ctx.restoreGState()
            }
        }
        // Landing zone flag and path lights.
        let flagGround = world.ground(at:94)
        rect(93,flagGround-68,3,68,0x92a499)
        polygon([CGPoint(x:96,y:flagGround-66),CGPoint(x:127,y:flagGround-62),CGPoint(x:127,y:flagGround-44),CGPoint(x:96,y:flagGround-48)],0xd4a268)
        rect(101,flagGround-61,4,11,0x283d40); rect(99,flagGround-57,9,3,0x283d40)
        for x in stride(from:112.0,to:304,by:48) {
            let y = world.ground(at:x)
            rect(x,y-5,6,5,0x263737); rect(x+1,y-7,4,3,0xa1d7b1)
            circle(x+3,y-6,10,0xa1d7b1,0.07)
        }
        let margin = view.insetBy(dx:-80,dy:-80)
        if chunkImages.count > world.chunks.count {
            // Keep the sections pieces broke off from until each piece has its own image.
            let alive = Set(world.chunks.flatMap{[$0.id,$0.parent]})
            chunkImages = chunkImages.filter{ alive.contains($0.key) }
        }
        // Pieces broken off a section this frame derive their image before the section's is dropped.
        for chunk in world.chunks where chunkImages[chunk.id] == nil && chunkImages[chunk.parent] != nil { _ = chunkImage(chunk) }
        for chunk in world.chunks where margin.insetBy(dx:-chunk.radius,dy:-chunk.radius).contains(NSPoint(x:chunk.position.x,y:chunk.position.y)) {
            ctx.saveGState()
            ctx.translateBy(x:chunk.position.x,y:chunk.position.y)
            ctx.rotate(by:chunk.angle)
            if let (image,offset) = chunkImage(chunk) {
                ctx.interpolationQuality = .none
                ctx.translateBy(x:offset.x,y:offset.y+Double(image.height)); ctx.scaleBy(x:1,y:-1)
                ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            ctx.restoreGState()
        }
        for w in world.wrecks where margin.contains(NSPoint(x:w.position.x,y:w.position.y)) { drawDrone(w) }
        // Water goes over falling sections and dead drones, so what lands in it is seen sinking through.
        drawWater(ctx,view)
        if (deployMenu && deployTab == .troops) || placingTroops { drawDeployZone(view) }
        for crate in world.crates where margin.insetBy(dx:-World.crateRadius,dy:-World.crateRadius).contains(NSPoint(x:crate.position.x,y:crate.position.y)) { drawCrate(crate) }
        for plane in world.planes where margin.insetBy(dx:-120,dy:-60).contains(NSPoint(x:plane.x,y:plane.y)) { drawPlane(plane) }
        for jet in world.jets where margin.insetBy(dx:-80,dy:-60).contains(NSPoint(x:jet.x,y:jet.path.y)) { drawJet(jet) }
        if let d = world.drone, margin.contains(NSPoint(x:d.position.x,y:d.position.y)) { drawDroneAim(d); drawDrone(d) }
        drawFireLayer(view)
        drawTrajectories(view)
        for s in world.soldiers where margin.contains(NSPoint(x:s.position.x,y:s.position.y)) { drawSoldier(s) }
        if isHovering, pointer.y > 104 && pointer.y < 808 {
            switch placing {
            case .troops(let i): drawPlacementGhost(World.offers[i])
            case .support(let i): drawSupportGhost(World.support[i])
            case nil: break
            }
        }
        for shot in world.shots {
            line([CGPoint(x:shot.previous.x,y:shot.previous.y),CGPoint(x:shot.position.x,y:shot.position.y)],0xffc878,3)
            rect(shot.position.x-2,shot.position.y-2,4,4,0xffe8b2)
        }
        for p in world.particles where margin.contains(NSPoint(x:p.position.x,y:p.position.y)) {
            let alpha = min(1,p.life / max(0.1,p.total)*1.5)
            if p.kind == World.sprayKind || p.kind == World.mistKind {
                rect(p.position.x-p.size/2,p.position.y-p.size/2,p.size,p.size,p.kind == World.sprayKind ? 0xd9eeee : 0xe4efee,p.kind == World.sprayKind ? alpha*0.85 : alpha*0.22)
                continue
            }
            rect(p.position.x-p.size/2,p.position.y-p.size/2,p.size,p.size,p.kind == 14 ? 0x2a2522 : palette[min(p.kind,9)],p.kind == 9 ? alpha*0.32 : p.kind == 14 ? alpha*0.42 : alpha)
        }
        for b in world.blasts {
            let progress = b.age/0.45
            if progress < 0.3 {
                circle(b.position.x,b.position.y,b.radius*(0.5+progress*2),0xffb251,1-progress*2)
                rect(b.position.x-10,b.position.y-10,20,20,0xffefd1,1-progress*3)
            }
            let ring = NSBezierPath(ovalIn:NSRect(x:b.position.x-b.radius*(1+progress),y:b.position.y-b.radius*(1+progress),width:b.radius*2*(1+progress),height:b.radius*2*(1+progress)))
            color(0xd8c8a0,(1-progress)*0.5).setStroke(); ring.lineWidth = 2; ring.stroke()
        }
        ctx.restoreGState()
        // Fine rain is atmosphere only; it never obscures commands.
        let fall = min(1.6,max(0.6,zoom))
        for n in 0..<120 {
            let x = (Double(n*113)+world.elapsed*28-camera.x*zoom*0.3).truncatingRemainder(dividingBy:1490)
            let y = 104+(Double(n*79)+world.elapsed*240).truncatingRemainder(dividingBy:704)
            let rx = x < 0 ? x+1465 : x-25
            line([CGPoint(x:rx,y:y),CGPoint(x:rx-4*fall,y:y+11*fall)],0xadc4c5,1,0.13)
        }
        if !inMenu { drawGrid(); drawAmmoTags(); drawCrateTags(); drawBomberTags() }
        // Sector names stay readable at every zoom level.
        for mark in world.landmarks {
            let p = toScreen(Vec(x:mark.x,y:mark.y))
            if p.x > -300 && p.x < 1440 && p.y > 110 && p.y < 770 {
                polygon([CGPoint(x:p.x-10,y:p.y+3),CGPoint(x:p.x-6,y:p.y+7),CGPoint(x:p.x-10,y:p.y+11),CGPoint(x:p.x-14,y:p.y+7)],Tac.amber,0.85)
                text(mark.name,p.x,p.y,10,0xd8c79a,.semibold,true)
            }
        }
        drawObjectiveMarkers()
        if (deployMenu && deployTab == .troops) || placingTroops {
            let a = toScreen(Vec(x:World.deployZone.lowerBound,y:0)).x, b = toScreen(Vec(x:World.deployZone.upperBound,y:0)).x
            if b > 0 && a < 1440 { text("▼ DEPLOYMENT ZONE",max(8,a)+8,166,10,Tac.green,.bold,true) }
        }
        if let target = world.target { crosshair(toScreen(target),Tac.red,true) }
        if isHovering && !inMenu && placing == nil && pointer.y > 104 && pointer.y < 808 && !minimapFrame.contains(NSPoint(x:pointer.x,y:pointer.y)) { crosshair(pointer,Tac.green,false) }
        ctx.restoreGState()
        // Faint scanlines and a viewport frame give the feed a sensor-display look.
        for y in stride(from:104.0,to:808,by:3) { rect(0,y,1440,1,0x000000,0.07) }
        brackets(NSRect(x:12,y:114,width:1416,height:656),Tac.text,22,0.55,2)
        // Depth fade into the command dock.
        NSGradient(starting:color(Tac.panel,0),ending:color(Tac.panel,0.85))!.draw(in:NSRect(x:0,y:718,width:1440,height:90),angle:90)
        if !inMenu { drawMinimap(ctx); drawObjectives(); drawStatusToast(); drawBriefing() }
        if help && !inMenu { drawHelp() }
        if deployMenu && !inMenu { drawDeployMenu() }
        if world.paused && !escMenu && !debrief {
            // A thin amber frame and a small tag, so the field stays clear for planning orders.
            brackets(NSRect(x:6,y:108,width:1428,height:668),Tac.amber,30,0.8,2)
            let tag = "■ PAUSED · ISSUE ORDERS · \(k(.pause)) RESUME"
            let w = textWidth(tag,9,.bold,true)+20, r = NSRect(x:720-w/2,y:112,width:w,height:20)
            panel(r,Tac.panel,0.85); rect(r.minX,r.minY,r.width,2,Tac.amber)
            text(tag,r.minX+10,r.minY+5,9,Tac.amber,.bold,true)
        }
    }
    /// A world-anchored range grid with edge ticks, drawn in screen space so lines stay crisp.
    func drawGrid() {
        let a = toWorld(Vec(x:0,y:104)), b = toWorld(Vec(x:1440,y:808))
        let step = zoom < 0.5 ? 400.0 : 100.0
        var x = floor(a.x/step)*step
        while x <= b.x {
            let sx = toScreen(Vec(x:x,y:0)).x
            let major = x.truncatingRemainder(dividingBy:400) == 0
            rect(sx,104,1,704,Tac.green,major ? 0.07 : 0.035)
            x += step
        }
        var y = floor(a.y/step)*step
        while y <= b.y {
            let sy = toScreen(Vec(x:0,y:y)).y
            if sy > 104 && sy < 808 {
                rect(0,sy,1440,1,Tac.green,0.035)
            }
            y += step
        }
    }
    func drawMinimap(_ ctx: CGContext) {
        let m = minimapFrame
        // One pixel per cell, refreshed a few times a second.
        if minimap == nil || world.elapsed-minimapClock > 0.25 || world.elapsed < minimapClock {
            minimapClock = world.elapsed
            var pixels = [UInt32](repeating:0,count:World.columns*World.rows)
            for i in pixels.indices {
                let v = world.voxels[i]
                let hex: UInt32 = v != 0 ? palette[Int(v)] : world.water.mass[i] > 0.3 ? 0x3b7480 : (world.backdrops[i] >= 0 ? 0x15272c : 0)
                if v != 0 || hex != 0 { pixels[i] = 0xff000000 | (hex & 0xff) << 16 | (hex >> 8 & 0xff) << 8 | hex >> 16 }
            }
            let data = Data(bytes:pixels,count:pixels.count*4) as CFData
            if let provider = CGDataProvider(data:data) {
                minimap = CGImage(width:World.columns,height:World.rows,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:World.columns*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
            }
        }
        panel(NSRect(x:m.minX-6,y:m.minY-6,width:m.width+12,height:m.height+30),Tac.panel,0.92)
        rect(m.minX,m.minY,m.width,m.height,0x141c15)
        if let minimap {
            ctx.saveGState(); ctx.interpolationQuality = .none
            ctx.translateBy(x:m.minX,y:m.maxY); ctx.scaleBy(x:1,y:-1)
            ctx.draw(minimap,in:CGRect(x:0,y:0,width:m.width,height:m.height))
            ctx.restoreGState()
        }
        let sx = Double(m.width)/World.width, sy = Double(m.height)/(World.bottom-World.top)
        let left = Double(m.minX), top = Double(m.minY)
        // Grid columns match the lettered squares on the main view.
        for gx in stride(from:400.0,to:World.width,by:400) { rect(left+gx*sx,top,1,m.height,Tac.green,0.12) }
        for crate in world.crates { rect(left+crate.position.x*sx-2,top+(crate.position.y-World.top)*sy-3,4,3,Tac.amber) }
        for plane in world.planes where plane.x > 0 && plane.x < World.width {
            let px = left+plane.x*sx, py = top+max(0,plane.y-World.top)*sy, h = plane.heading
            polygon([CGPoint(x:px+4*h,y:py),CGPoint(x:px-3*h,y:py-3),CGPoint(x:px-3*h,y:py+3)],Tac.amber)
        }
        for jet in world.jets where jet.x > 0 && jet.x < World.width {
            let px = left+jet.x*sx, py = top+max(0,jet.path.y-World.top)*sy, h = jet.heading
            polygon([CGPoint(x:px+4*h,y:py),CGPoint(x:px-3*h,y:py-2),CGPoint(x:px-3*h,y:py+2)],Tac.red)
        }
        if let d = world.drone, d.position.x > 0 && d.position.x < World.width {
            let px = left+d.position.x*sx, py = top+max(0,d.position.y-World.top)*sy
            rect(px-2,py-2,4,4,Tac.red); brackets(NSRect(x:px-4,y:py-4,width:8,height:8),Tac.red,2,0.9,1)
        }
        drawFireMinimap(left:left,top:top,sx:sx,sy:sy)
        for s in world.soldiers { rect(left+s.position.x*sx-1,top+(s.position.y-World.top)*sy-3,2,3,s.outOfAmmo ? Tac.red : s.lowAmmo ? Tac.amber : s.selected ? Tac.green : Tac.bright) }
        if let target = world.target {
            let t = Vec(x:left+target.x*sx,y:top+(target.y-World.top)*sy)
            let pulse = 3+2*abs(sin(world.elapsed*4))
            rect(t.x-1.5,t.y-1.5,3,3,Tac.red)
            brackets(NSRect(x:t.x-pulse,y:t.y-pulse,width:pulse*2,height:pulse*2),Tac.red,2,0.9,1)
        }
        let a = toWorld(Vec(x:0,y:104)), b = toWorld(Vec(x:1440,y:808))
        let view = NSRect(x:left+max(0,a.x)*sx,y:top+max(0,a.y-World.top)*sy,width:(min(World.width,b.x)-max(0,a.x))*sx,height:max(2,(min(World.bottom,b.y)-max(World.top,a.y))*sy))
        rect(view.minX,view.minY,view.width,view.height,Tac.amber,0.08)
        brackets(view,Tac.amber,min(6,view.width/3),0.95,1)
        line([CGPoint(x:m.minX,y:m.minY),CGPoint(x:m.maxX,y:m.minY),CGPoint(x:m.maxX,y:m.maxY),CGPoint(x:m.minX,y:m.maxY),CGPoint(x:m.minX,y:m.minY)],Tac.rule)
        text("TAC MAP",m.minX,m.maxY+5,9,Tac.green,.bold,true)
    }
    /// Faded dashed arcs from each attacking soldier to where its next round should land,
    /// brighter toward the impact and for selected soldiers. Drawn in world space.
    func drawTrajectories(_ view: NSRect) {
        let width = 1.5/zoom
        for s in world.soldiers {
            guard let path = world.trajectory(of:s), path.count > 1 else { continue }
            let strength = s.selected ? 0.42 : 0.2, c = s.selected ? Tac.green : Tac.text
            for i in stride(from:0,to:path.count-1,by:2) where view.insetBy(dx:-20,dy:-20).contains(NSPoint(x:path[i].x,y:path[i].y)) {
                let a = strength*(0.25+0.75*Double(i)/Double(path.count-1))
                line([CGPoint(x:path[i].x,y:path[i].y),CGPoint(x:path[i+1].x,y:path[i+1].y)],c,width,a)
            }
            if let end = path.last { circle(end.x,end.y,3/zoom,c,strength) }
        }
        // RPG gunners have no target: with only gunners selected, each one's line previews
        // the rocket it would fire at the pointer, ending in the blast it would leave.
        guard aimingRockets else { return }
        let aim = toWorld(pointer)
        for s in world.soldiers where s.selected {
            guard let path = world.rocketTrajectory(of:s,at:aim), path.count > 1 else { continue }
            for i in stride(from:0,to:path.count-1,by:2) where view.insetBy(dx:-20,dy:-20).contains(NSPoint(x:path[i].x,y:path[i].y)) {
                line([CGPoint(x:path[i].x,y:path[i].y),CGPoint(x:path[i+1].x,y:path[i+1].y)],Tac.amber,width*1.3,0.35+0.4*Double(i)/Double(path.count-1))
            }
            if let end = path.last {
                circle(end.x,end.y,3/zoom,Tac.amber,0.8)
                let r = s.kind.blastRadius, ring = NSBezierPath(ovalIn:NSRect(x:end.x-r,y:end.y-r,width:r*2,height:r*2))
                ring.lineWidth = width; color(Tac.amber,0.4).setStroke(); ring.stroke()
            }
        }
    }
    /// Whether the pointer is aiming rockets: only RPG gunners are selected and it is over the
    /// battlefield with no menu or placement in the way.
    var aimingRockets: Bool {
        world.rocketsSelected && isHovering && !inMenu && !escMenu && !debrief && !deployMenu && placing == nil
            && pointer.y > 104 && pointer.y < 808 && !minimapFrame.contains(NSPoint(x:pointer.x,y:pointer.y))
    }
    func drawSoldier(_ s: Soldier, ghost: Bool = false) {
        // The sprite is authored at full size around its feet and drawn scaled down.
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        if ghost { ctx.setAlpha(0.5) }
        let k = Soldier.drawScale
        ctx.translateBy(x:floor(s.position.x),y:floor(s.position.y)); ctx.scaleBy(x:k,y:k)
        let x = 0.0, y = 0.0
        if s.selected {
            brackets(NSRect(x:x-14,y:y-44,width:28,height:48),Tac.green,6,0.9,1.5)
            polygon([CGPoint(x:x-4,y:y-52),CGPoint(x:x+4,y:y-52),CGPoint(x:x,y:y-47)],Tac.green)
        }
        circle(x,y+1,12,0x0b2025,0.3)
        let walk = s.moveX != nil ? sin(s.stride)*4 : 0
        rect(x-6+walk,y-11,5,10,0x26353a); rect(x+2-walk,y-11,5,10,0x26353a)
        rect(x-8+walk,y-3,7,3,0x15282e); rect(x+2-walk,y-3,7,3,0x15282e)
        rect(x-7,y-26,14,16,0x85917a); rect(x-7,y-24,4,13,0x536f68)
        rect(x-4,y-22,9,9,0x4d645e); rect(x-3,y-20,2,4,0xb6b38e); rect(x+1,y-20,2,4,0xb6b38e)
        rect(x-s.facing*9-3,y-25,5,13,0x465e58)
        rect(x-5,y-34,11,9,0xc8b497); rect(x+s.facing*4,y-32,3,3,0x253b40)
        rect(x-7,y-38,14,7,0x82937d); rect(x-8,y-33,17,3,0x455f5b)
        rect(x-3,y-37,6,2,0xa7b096)
        rect(x+s.facing*5-3,y-23,7,5,0xb7a585)
        let gunX = s.facing > 0 ? x+5 : x-23
        if s.kind == .grenadier {
            // Helmet band and a stubby, wide-bore launcher.
            rect(x-8,y-33,17,2,Tac.amber)
            rect(gunX,y-27,18,8,0x2c3329); rect(s.facing > 0 ? gunX+15 : gunX,y-28,3,10,0x1a1f1a)
        } else if s.kind == .rpg {
            // Red helmet band and a long tube over the shoulder with its warhead at the mouth.
            let f = s.facing
            rect(x-8,y-33,17,2,Tac.red)
            rect(min(x-f*14,x+f*24),y-30,38,6,0x3a4433); rect(min(x-f*14,x-f*10),y-30,4,6,0x1a1f1a)
            rect(min(x+f*2,x+f*8),y-24,6,4,0x2c3329)
            polygon([CGPoint(x:x+f*24,y:y-31),CGPoint(x:x+f*29,y:y-32),CGPoint(x:x+f*34,y:y-27),CGPoint(x:x+f*29,y:y-22),CGPoint(x:x+f*24,y:y-23)],0x6b6a3e)
        } else {
            rect(gunX,y-25,18,5,0x22373d); rect(gunX+2,y-25,12,1,0x8a9e96)
        }
        rect(x+s.facing*12-2,y-21,4,5,0x24383a)
        if s.flash > 0 && s.kind == .rpg {
            // Flame from the mouth and backblast out of the rear of the tube.
            let mouth = x+s.facing*34, rear = x-s.facing*15
            polygon([CGPoint(x:mouth,y:y-32),CGPoint(x:mouth+s.facing*10,y:y-27),CGPoint(x:mouth,y:y-22)],0xffd48b)
            polygon([CGPoint(x:rear,y:y-31),CGPoint(x:rear-s.facing*16,y:y-36),CGPoint(x:rear-s.facing*20,y:y-27),CGPoint(x:rear-s.facing*16,y:y-18),CGPoint(x:rear,y:y-23)],0xffb251,0.85)
        } else if s.flash > 0 {
            let muzzle = x+s.facing*27
            polygon([CGPoint(x:muzzle-6,y:y-22),CGPoint(x:muzzle,y:y-30),CGPoint(x:muzzle+7,y:y-23),CGPoint(x:muzzle,y:y-16)],0xffd48b)
        }
    }
    func crosshair(_ p:Vec,_ c:UInt32,_ locked:Bool) {
        let r = locked ? 18.0 : 12.0
        line([CGPoint(x:p.x-r-8,y:p.y),CGPoint(x:p.x-r+4,y:p.y)],c,1.5)
        line([CGPoint(x:p.x+r-4,y:p.y),CGPoint(x:p.x+r+8,y:p.y)],c,1.5)
        line([CGPoint(x:p.x,y:p.y-r-8),CGPoint(x:p.x,y:p.y-r+4)],c,1.5)
        line([CGPoint(x:p.x,y:p.y+r-4),CGPoint(x:p.x,y:p.y+r+8)],c,1.5)
        rect(p.x-1,p.y-1,2,2,c)
        if locked {
            // Rotating lock ring with a pulsing bracket box.
            let spin = world.elapsed*1.5
            for q in 0..<4 {
                let arc = NSBezierPath(); let start = Double(q)*90+spin*57.3+15
                arc.appendArc(withCenter:NSPoint(x:p.x,y:p.y),radius:r,startAngle:start,endAngle:start+60); arc.lineWidth = 1.5
                color(c,0.85).setStroke(); arc.stroke()
            }
            let pad = r+6+2*abs(sin(world.elapsed*5))
            brackets(NSRect(x:p.x-pad,y:p.y-pad,width:pad*2,height:pad*2),c,6,0.9)
            text("TARGET",p.x+pad+6,p.y-pad,9,c,.bold,true)
        } else {
            let path = NSBezierPath(ovalIn:NSRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)); path.lineWidth=1; color(c,0.35).setStroke(); path.stroke()
        }
    }
    /// Field guide: the objective and every control, so the HUD itself needs no hint text.
    let guideFrame = NSRect(x:30,y:124,width:364,height:414)
    func drawHelp() {
        let r = guideFrame
        panel(r,Tac.panel,0.94); rect(r.minX,r.minY,r.width-10,22,Tac.amber,0.14); rect(r.minX,r.minY,3,r.height,Tac.amber)
        text("▲ FIELD GUIDE",r.minX+14,r.minY+4,11,Tac.amber,.bold,true)
        text("Destroy infrastructure to score.",r.minX+14,r.minY+32,13,Tac.bright,.semibold)
        let steps = ["[\(k(.troops))] Spend credits on troops.","Click structures to open fire.","HVTs pay triple, plus a bonus.","Reach \(World.requirement/1000)K PTS, then press \(k(.extract))."]
        for (i,step) in steps.enumerated() {
            let y = r.minY+60+Double(i)*24
            rect(r.minX+14,y,22,17,Tac.amber,0.15)
            text(String(format:"%02d",i+1),r.minX+17,y+2,10,Tac.amber,.bold,true)
            text(step,r.minX+46,y,12,Tac.text)
        }
        let cy = r.minY+168
        rect(r.minX+14,cy,r.width-28,1,Tac.rule)
        text("CONTROLS",r.minX+14,cy+8,9,Tac.dim,.bold,true)
        let pan = [KeyAction.panLeft,.panRight,.panUp,.panDown].allSatisfy{ binds.key($0) == $0.defaultKey } ? "ARROWS" : [KeyAction.panLeft,.panRight,.panUp,.panDown].map{k($0)}.joined(separator:"/")
        let controls = [("CLICK","Attack / select · fire RPG"),("SHIFT-CLICK · DRAG","Add / remove · box-select"),("RIGHT-CLICK","Move selected soldiers"),
                        ("\(k(.selectAll))  ·  ESC","Select all / none  ·  deselect"),("SCROLL / PINCH","Zoom"),("\(pan) / 2-FINGER","Pan  ·  \(k(.centre)) centres on troops"),
                        ("\(k(.pause))  ·  \(k(.speed))","Pause  ·  change speed"),("ESC","Menu: settings, restart, exit")]
        for (i,c) in controls.enumerated() {
            let y = cy+28+Double(i)*22
            text(c.0,r.minX+14,y+1,9,Tac.amber,.bold,true)
            text(c.1,r.minX+150,y,11,Tac.text)
        }
        text("CLICK OR PRESS \(k(.guide) == "F1" ? "F1" : k(.guide)+" / F1") TO CLOSE OR REOPEN",r.minX+14,r.maxY-22,9,Tac.dim,.medium,true)
    }
    let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss'Z'"; f.timeZone = TimeZone(identifier:"UTC"); return f }()
    func levelCard(_ i:Int) -> NSRect { NSRect(x:96,y:282+Double(i)*46,width:584,height:40) }
    /// The operation Enter starts and the radar shows when no card is hovered: the first one
    /// not yet cleared.
    var nextLevel: Int { min(levels.count-1,world.cleared) }
    var hoveredLevel: Int? { isHovering ? levels.indices.first { levelCard($0).contains(NSPoint(x:pointer.x,y:pointer.y)) } : nil }
    func drawMenu() {
        let t = ProcessInfo.processInfo.systemUptime
        let blink = Int(t*2) % 2 == 0
        rect(0,0,1440,900,0x070a07,0.93)
        for x in stride(from:0.0,to:1440,by:48) { rect(x,0,1,900,Tac.green,0.035) }
        for y in stride(from:0.0,to:900,by:48) { rect(0,y,1440,1,Tac.green,0.035) }
        for y in stride(from:0.0,to:900,by:3) { rect(0,y,1440,1,0x000000,0.12) }
        brackets(NSRect(x:24,y:34,width:1392,height:832),Tac.amber,28,0.7,2)
        // Terminal status row.
        text("◆ RH-TAC  //  COMMAND TERMINAL",48,46,10,Tac.dim,.bold,true)
        circle(1196,53,3,Tac.green,blink ? 1 : 0.25)
        text("SECURE LINK",1206,46,10,Tac.green,.bold,true)
        text(clock.string(from:Date()),1306,46,10,Tac.text,.medium,true)
        rect(48,68,1344,1,Tac.rule,0.7)
        // Title block.
        text("TACTICAL DESTRUCTION SIMULATOR",98,112,11,Tac.amber,.bold,true)
        rect(96,134,5,64,Tac.amber)
        text("RAINING HELL",120,128,56,Tac.bright,.heavy,true)
        text("v0.3.0 RC1  //  ALPHA BUILD  //  \(levels.count) OPERATIONS",122,208,10,Tac.dim,.medium,true)
        rect(96,244,584,1,Tac.rule)
        text("▸ SELECT OPERATION",96,258,11,Tac.amber,.bold,true)
        let open = levels.indices.filter { world.unlocked($0) }.count
        text(String(format:"%02d / %02d AVAILABLE",open,levels.count),560,258,10,Tac.dim,.medium,true)
        for (i,level) in levels.enumerated() {
            let r = levelCard(i), open = world.unlocked(i), done = i < world.cleared
            let hovered = open && hoveredLevel == i
            let accent = !open ? Tac.rule : hovered ? Tac.green : Tac.amber
            panel(r,hovered ? Tac.hover : Tac.raised,open ? 0.94 : 0.6,hovered ? Tac.green : Tac.rule,10)
            rect(r.minX,r.minY,4,r.height,accent)
            if hovered { brackets(r.insetBy(dx:-5,dy:-5),accent,10,1) }
            text(String(format:"OP-%02d  ·  ",i+1)+level.operation,r.minX+16,r.minY+6,9,accent,.heavy,true)
            text(level.name,r.minX+16,r.minY+17,15,open ? Tac.bright : Tac.dim,.heavy,true)
            // Size, goal and opening funds, so the player can pick with open eyes.
            let stats = [("FRONT",String(format:"%.1f KM",Double(level.columns)*World.cell*Double(World.scale)/1000)),
                         ("GOAL","\(level.requirement/1000)K PTS"),("GRANT · \(level.funds.name)",cr(level.grant))]
            for (k,stat) in stats.enumerated() {
                let x = r.minX+262+Double(k)*82
                text(stat.0,x,r.minY+7,8,Tac.dim,.bold,true)
                text(stat.1,x,r.minY+20,11,open ? Tac.text : Tac.dim,.semibold,true)
            }
            let state = done ? "CLEARED" : open ? "READY" : "LOCKED"
            text(state,r.maxX-62,r.minY+20,9,done || open ? Tac.green : Tac.dim,.bold,true)
            if hovered { text(blink ? "DEPLOY ▸" : "DEPLOY ▹",r.maxX-62,r.minY+6,9,Tac.green,.heavy,true) }
            else if open { text("[\(i+1)]",r.maxX-62,r.minY+6,9,Tac.text,.bold,true) }
            else { text("CLEAR OP-\(String(format:"%02d",i))",r.maxX-62,r.minY+6,7,Tac.dim,.bold,true) }
        }
        drawRadar(t)
        rect(48,840,1344,1,Tac.rule,0.7)
        drawBank()
        drawCheatBox(blink)
        drawDevMode(t)
        text("▸ CLICK AN OPERATION, PRESS ITS NUMBER OR ENTER TO DEPLOY · ← → / A D SET WITHDRAWAL",48,850,10,Tac.dim,.medium,true)
        let keys = "[S] SETTINGS  //  [F] FULL SCREEN"
        text(keys,1392-textWidth(keys,10,.medium,true),850,10,Tac.dim,.medium,true)
        drawSettingsButton()
        if lobbySettings { drawLobbySettings() }
    }
    /// Square gear button in the lobby's terminal row that opens the settings.
    func drawSettingsButton() {
        let b = settingsButton, hovered = (isHovering && !lobbySettings && b.contains(NSPoint(x:pointer.x,y:pointer.y))) || lobbySettings
        let bg = hovered ? Tac.hover : Tac.panel, accent = hovered ? Tac.green : Tac.text
        rect(b.minX,b.minY,b.width,b.height,bg,0.9)
        line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],hovered ? Tac.green : Tac.rule)
        gear(b.midX,b.midY,9,accent,bg)
        if hovered && !lobbySettings { text("SETTINGS",b.minX-textWidth("SETTINGS",9,.bold,true)-8,b.minY+9,9,Tac.green,.bold,true) }
    }
    /// An eight-toothed cog with a hole punched through in `hole`.
    func gear(_ cx:Double,_ cy:Double,_ r:Double,_ c:UInt32,_ hole:UInt32) {
        var pts: [CGPoint] = []
        for k in 0..<8 {
            let a = Double(k) * .pi/4
            for (da,rr) in [(-0.34,r*0.72),(-0.2,r),(0.2,r),(0.34,r*0.72)] { pts.append(CGPoint(x:cx+cos(a+da)*rr,y:cy+sin(a+da)*rr)) }
        }
        polygon(pts,c)
        circle(cx,cy,r*0.34,hole)
    }
    func settingsTabRect(_ tab: SettingsTab) -> NSRect {
        let tabs = settingsTabs, w = (392-4*Double(tabs.count-1))/Double(tabs.count)
        return NSRect(x:524+Double(tabs.firstIndex(of:tab) ?? 0)*(w+4),y:250,width:w,height:24)
    }
    /// Danger zone rows sit in one red-bordered box, GitHub style: description left, button right.
    let dangerBox = NSRect(x:524,y:318,width:392,height:156)
    func dangerRow(_ a: DangerAction) -> NSRect { NSRect(x:dangerBox.minX,y:dangerBox.minY+(a == .deleteSave ? 0 : 78),width:dangerBox.width,height:78) }
    func dangerButton(_ a: DangerAction) -> NSRect { let r = dangerRow(a); return NSRect(x:r.maxX-136,y:r.midY-17,width:120,height:34) }
    func dangerDetail(_ a: DangerAction) -> (String,String) {
        switch a {
        case .deleteSave: return (world.bank > 0 ? "ERASES \(cr(world.bank)) BANKED CREDITS AND CLEARED OPERATIONS." : "ERASES BANKED CREDITS AND CLEARED OPERATIONS.","ONCE DELETED, IT CANNOT BE RECOVERED.")
        case .resetSettings: return ("SOUND ON AT \(Int(GameAudio.defaultVolume*100))% VOLUME, DEFAULT KEYS.","YOUR SAVE DATA IS KEPT.")
        }
    }
    func drawLobbySettings() {
        rect(0,0,1440,900,0x070a07,0.88)
        for y in stride(from:0.0,to:900,by:3) { rect(0,y,1440,1,0x000000,0.12) }
        let frame = NSRect(x:500,y:160,width:440,height:470)
        panel(frame,Tac.panel,0.97,Tac.rule,16)
        brackets(frame.insetBy(dx:-9,dy:-9),settingsTab == .danger ? Tac.red : Tac.amber,18,0.85,2)
        rect(500,160,424,28,Tac.amber,0.9)
        text("■ SETTINGS",514,167,10,0x1a1408,.heavy,true)
        text("COMMAND TERMINAL",800,167,10,0x1a1408,.heavy,true)
        rect(524,212,5,30,Tac.amber)
        text("SETTINGS",540,206,26,Tac.bright,.heavy,true)
        drawSettingsTabs()
        rect(524,280,392,1,Tac.rule)
        switch settingsTab {
        case .general: drawSettingRows("RETURN TO THE MAIN MENU")
        case .controls: drawControls()
        case .danger: drawDangerZone()
        }
        rect(524,580,392,1,Tac.rule,0.6)
        if settingsTab == .controls { drawControlsFooter() }
        else { text(settingsTab == .danger ? "THESE ACTIONS CANNOT BE UNDONE   //   [TAB] GENERAL" : "SETTINGS ARE SAVED AUTOMATICALLY   //   [TAB] CONTROLS",526,594,9,Tac.dim,.medium,true) }
        if let confirming { drawDangerConfirm(confirming) }
    }
    /// The tab strip under the settings title, shared by the lobby and the pause menu.
    func drawSettingsTabs() {
        for tab in settingsTabs {
            let r = settingsTabRect(tab), on = settingsTab == tab, hovered = confirming == nil && escHovered(r)
            let accent = tab == .danger ? Tac.red : Tac.green
            rect(r.minX,r.minY,r.width,r.height,on ? Tac.raised : hovered ? Tac.hover : 0x000000,on || hovered ? 1 : 0.3)
            if on { rect(r.minX,r.maxY-2,r.width,2,accent) }
            let label = tab == .general ? "GENERAL" : tab == .controls ? "CONTROLS" : "⚠ DANGER ZONE"
            text(label,r.midX-textWidth(label,10,.heavy,true)/2,r.minY+6,10,on ? (tab == .danger ? Tac.red : Tac.bright) : hovered ? accent : Tac.dim,.heavy,true)
        }
    }
    /// CONTROLS tab: every rebindable action in two columns, its key boxed on the right.
    func controlCell(_ i: Int) -> NSRect { NSRect(x:524+Double(i/11)*200,y:290+Double(i%11)*26,width:192,height:24) }
    func controlKeyBox(_ i: Int) -> NSRect { let r = controlCell(i); return NSRect(x:r.maxX-70,y:r.minY+3,width:64,height:18) }
    let resetKeysButton = NSRect(x:836,y:588,width:80,height:22)
    func drawControls() {
        let blink = Int(ProcessInfo.processInfo.systemUptime*2) % 2 == 0
        for (i,a) in KeyAction.allCases.enumerated() {
            let r = controlCell(i), b = controlKeyBox(i), active = rebinding == a
            let hovered = rebinding == nil && escHovered(r), changed = binds.key(a) != a.defaultKey
            rect(r.minX,r.minY,r.width,r.height,active ? Tac.hover : hovered ? Tac.hover : Tac.raised,active || hovered ? 1 : 0.8)
            rect(r.minX,r.minY,2,r.height,active ? Tac.amber : hovered ? Tac.green : changed ? Tac.amber : Tac.rule,changed || active || hovered ? 1 : 0.8)
            text(a.title,r.minX+10,r.minY+7,9,active ? Tac.amber : Tac.bright,.bold,true)
            rect(b.minX,b.minY,b.width,b.height,0x000000,0.4)
            line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],active ? Tac.amber : hovered ? Tac.green : Tac.rule)
            let label = active ? (blink ? "PRESS…" : "") : k(a)
            text(label,b.midX-textWidth(label,9,.bold,true)/2,b.minY+4,9,active ? Tac.amber : changed ? Tac.amber : Tac.text,.bold,true)
        }
    }
    func drawControlsFooter() {
        let hint = rebindNote ?? (rebinding != nil ? "PRESS A KEY  //  [ESC] CANCEL  //  [⌫] DEFAULT" : "CLICK AN ACTION, THEN PRESS ITS NEW KEY")
        text(hint,526,594,9,rebindNote != nil ? Tac.red : rebinding != nil ? Tac.amber : Tac.dim,.medium,true)
        let b = resetKeysButton, on = !binds.isDefault, over = on && rebinding == nil && escHovered(b)
        rect(b.minX,b.minY,b.width,b.height,over ? Tac.hover : 0x000000,over ? 1 : 0.35)
        line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],over ? Tac.green : Tac.rule)
        text("RESET ALL",b.midX-textWidth("RESET ALL",9,.bold,true)/2,b.minY+6,9,on ? (over ? Tac.green : Tac.text) : Tac.rule,.bold,true)
    }
    /// Clicks on the CONTROLS tab: pick an action to rebind, or reset every key.
    func controlsMouseDown(_ p: NSPoint) {
        if let i = KeyAction.allCases.indices.first(where:{ controlCell($0).contains(p) }) {
            let a = KeyAction.allCases[i]
            rebinding = rebinding == a ? nil : a
            sound.play(SoundEvent(cue:.select))
        } else if rebinding != nil { rebinding = nil }
        else if resetKeysButton.contains(p) && !binds.isDefault { binds.resetAll(); sound.play(SoundEvent(cue:.reset)) }
        needsDisplay = true
    }
    /// Takes the next key for the action being rebound. Esc cancels; Delete restores the default.
    func rebindKeyDown(_ event: NSEvent) {
        guard let a = rebinding else { return }
        switch event.keyCode {
        case 53: rebinding = nil; sound.play(SoundEvent(cue:.select))
        case 51, 117: binds.reset(a); rebinding = nil; sound.play(SoundEvent(cue:.select))
        default:
            if binds.bind(a,event.keyCode) { rebinding = nil; sound.play(SoundEvent(cue:.select)) }
            else { rebindNote = "THAT KEY IS RESERVED  //  [ESC] CANCEL"; sound.play(SoundEvent(cue:.cease)) }
        }
        needsDisplay = true
    }
    func drawDangerZone() {
        text("DANGER ZONE",524,294,11,Tac.red,.heavy,true)
        let box = dangerBox
        rect(box.minX,box.minY,box.width,box.height,Tac.red,0.04)
        line([CGPoint(x:box.minX,y:box.minY),CGPoint(x:box.maxX,y:box.minY),CGPoint(x:box.maxX,y:box.maxY),CGPoint(x:box.minX,y:box.maxY),CGPoint(x:box.minX,y:box.minY)],Tac.red,1,0.8)
        for a in DangerAction.allCases {
            let r = dangerRow(a), b = dangerButton(a), (first,second) = dangerDetail(a)
            if a != DangerAction.allCases[0] { rect(r.minX,r.minY,r.width,1,Tac.red,0.35) }
            text(a.title,r.minX+16,r.minY+16,14,Tac.bright,.heavy,true)
            text(first,r.minX+16,r.minY+38,9,Tac.dim,.medium,true)
            text(second,r.minX+16,r.minY+52,9,Tac.dim,.medium,true)
            let hovered = confirming == nil && escHovered(b)
            rect(b.minX,b.minY,b.width,b.height,hovered ? Tac.red : 0x000000,hovered ? 0.95 : 0.35)
            line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],Tac.red,1,hovered ? 1 : 0.7)
            text(a.button,b.midX-textWidth(a.button,10,.heavy,true)/2,b.minY+11,10,hovered ? 0x1a0a08 : Tac.red,.heavy,true)
        }
        let r3 = escButton(3), over = confirming == nil && escHovered(r3)
        escRow(r3,"[ESC]","BACK","RETURN TO THE MAIN MENU",over)
        if over { text("◂",r3.maxX-28,r3.minY+16,16,Tac.green,.bold,true) }
    }
    /// The confirm button on the danger pop-up, and its cancel button beside it.
    func confirmButton(_ cancel: Bool) -> NSRect { NSRect(x:cancel ? 806 : 538,y:516,width:cancel ? 96 : 258,height:44) }
    var confirmField: NSRect { NSRect(x:538,y:462,width:364,height:32) }
    var confirmReady: Bool { confirming.map { confirmEntry.uppercased() == $0.word } ?? false }
    /// GitHub-style confirmation: say what will be lost, then make the player type a word.
    func drawDangerConfirm(_ a: DangerAction) {
        let blink = Int(ProcessInfo.processInfo.systemUptime*2) % 2 == 0
        rect(0,0,1440,900,0x000000,0.6)
        let box = NSRect(x:520,y:300,width:400,height:278)
        panel(box,Tac.panel,1,Tac.red,12)
        brackets(box.insetBy(dx:-7,dy:-7),Tac.red,14,0.9,2)
        rect(box.minX+18,box.minY+22,4,30,Tac.red)
        text(a.title+"?",box.minX+32,box.minY+20,20,Tac.bright,.heavy,true)
        text("THIS CANNOT BE UNDONE",box.minX+34,box.minY+50,9,Tac.red,.bold,true)
        rect(box.minX+18,box.minY+74,box.width-36,52,Tac.red,0.1)
        rect(box.minX+18,box.minY+74,2,52,Tac.red)
        let (first,second) = dangerDetail(a)
        text(first,box.minX+30,box.minY+84,10,Tac.text,.medium,true)
        text(second,box.minX+30,box.minY+102,10,Tac.text,.medium,true)
        text("TYPE \(a.word) TO CONFIRM",box.minX+18,box.minY+142,9,Tac.dim,.bold,true)
        let f = confirmField
        rect(f.minX,f.minY,f.width,f.height,0x000000,0.4)
        line([CGPoint(x:f.minX,y:f.minY),CGPoint(x:f.maxX,y:f.minY),CGPoint(x:f.maxX,y:f.maxY),CGPoint(x:f.minX,y:f.maxY),CGPoint(x:f.minX,y:f.minY)],confirmReady ? Tac.red : Tac.text)
        if confirmEntry.isEmpty { text(a.word,f.minX+10,f.minY+8,13,Tac.rule,.semibold,true) }
        text(confirmEntry.uppercased(),f.minX+10,f.minY+8,13,Tac.bright,.semibold,true)
        if blink { rect(f.minX+11+textWidth(confirmEntry.uppercased(),13,.semibold,true),f.minY+7,1.5,f.height-14,Tac.text) }
        let go = confirmButton(false), overGo = confirmReady && escHovered(go)
        rect(go.minX,go.minY,go.width,go.height,confirmReady ? Tac.red : 0x000000,confirmReady ? (overGo ? 1 : 0.8) : 0.35)
        line([CGPoint(x:go.minX,y:go.minY),CGPoint(x:go.maxX,y:go.minY),CGPoint(x:go.maxX,y:go.maxY),CGPoint(x:go.minX,y:go.maxY),CGPoint(x:go.minX,y:go.minY)],confirmReady ? Tac.red : Tac.rule)
        let label = "I UNDERSTAND, " + a.button
        text(label,go.midX-textWidth(label,11,.heavy,true)/2,go.minY+15,11,confirmReady ? 0x1a0a08 : Tac.rule,.heavy,true)
        let no = confirmButton(true), overNo = escHovered(no)
        panel(no,overNo ? Tac.hover : Tac.raised,1,overNo ? Tac.text : Tac.rule,6)
        text("CANCEL",no.midX-textWidth("CANCEL",11,.heavy,true)/2,no.minY+9,11,Tac.bright,.heavy,true)
        text("[ESC]",no.midX-textWidth("[ESC]",8,.bold,true)/2,no.minY+27,8,Tac.dim,.bold,true)
    }
    func openLobbySettings() {
        cheatOpen = false; cheatEntry = ""
        lobbySettings = true; settingsTab = .general; confirming = nil
        sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    func closeLobbySettings() {
        lobbySettings = false; confirming = nil; rebinding = nil
        sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    func showSettingsTab(_ tab: SettingsTab) {
        rebinding = nil
        guard tab != settingsTab else { return }
        settingsTab = tab; sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    /// Tab steps through the settings tabs and wraps around.
    func nextSettingsTab() {
        let tabs = settingsTabs
        showSettingsTab(tabs[((tabs.firstIndex(of:settingsTab) ?? 0)+1) % tabs.count])
    }
    func askToConfirm(_ a: DangerAction) { confirming = a; confirmEntry = ""; sound.play(SoundEvent(cue:.cease)); needsDisplay = true }
    /// Runs the confirmed danger action once its word has been typed.
    func performDanger() {
        guard let a = confirming, confirmReady else { sound.play(SoundEvent(cue:.cease)); return }
        switch a {
        case .deleteSave:
            world.bank = 0; withdrawal = 0; world.cleared = 0
            if persistent { UserDefaults.standard.removeObject(forKey:"bank"); UserDefaults.standard.removeObject(forKey:"cleared") }
        case .resetSettings:
            sound.resetSettings(); binds.resetAll()
            if persistent { UserDefaults.standard.removeObject(forKey:"fullScreen") }
        }
        confirming = nil; confirmEntry = ""
        sound.play(SoundEvent(cue:.reset)); needsDisplay = true
    }
    func lobbySettingsMouseDown(_ p: NSPoint) {
        if confirming != nil {
            if confirmButton(true).contains(p) { confirming = nil; sound.play(SoundEvent(cue:.select)) }
            else if confirmButton(false).contains(p) { performDanger() }
            return
        }
        if let tab = settingsTabs.first(where:{ settingsTabRect($0).contains(p) }) { showSettingsTab(tab); return }
        if settingsTab == .general { settingsMouseDown(p); return }
        if settingsTab == .controls { controlsMouseDown(p); return }
        if let a = DangerAction.allCases.first(where:{ dangerButton($0).contains(p) }) { askToConfirm(a) }
        else if escButton(3).contains(p) { closeLobbySettings() }
    }
    func lobbySettingsKeyDown(_ key: String?,_ event: NSEvent) {
        if confirming != nil {
            switch event.keyCode {
            case 53: confirming = nil; sound.play(SoundEvent(cue:.select))
            case 51: if !confirmEntry.isEmpty { confirmEntry.removeLast() }
            case 36, 76: performDanger()
            default:
                let typed = (event.characters ?? "").filter { $0.isLetter }
                if !typed.isEmpty && confirmEntry.count < 12 { confirmEntry += String(typed.prefix(12-confirmEntry.count)) }
            }
            needsDisplay = true
            return
        }
        if rebinding != nil { rebindKeyDown(event); return }
        if event.keyCode == Self.tabKey { nextSettingsTab(); return }
        switch key {
        case "\u{1b}", "\u{7f}", "s": closeLobbySettings()
        case "f": window?.toggleFullScreen(nil)
        case "m" where settingsTab == .general: chooseSetting(0)
        case "[", "-": sound.adjustVolume(-0.1)
        case "]", "=", "+": sound.adjustVolume(0.1)
        default: super.keyDown(with:event)
        }
        needsDisplay = true
    }
    func drawCheatBox(_ blink: Bool) {
        let b = cheatButton, hovered = isHovering && b.contains(NSPoint(x:pointer.x,y:pointer.y))
        let accent = devMode ? Tac.green : hovered || cheatOpen ? Tac.text : Tac.rule
        func outline(_ r: NSRect, _ c: UInt32) {
            line([CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.minX,y:r.minY)],c)
        }
        rect(b.minX,b.minY,b.width,b.height,hovered ? Tac.hover : Tac.panel,0.9)
        outline(b,accent)
        // A small chevron, pointing right when closed and left when open.
        let (cx,cy) = (b.midX,b.midY), d = cheatOpen ? -1.0 : 1.0
        line([CGPoint(x:cx-3*d,y:cy-5),CGPoint(x:cx+3*d,y:cy),CGPoint(x:cx-3*d,y:cy+5)],accent,1.5)
        guard cheatOpen else { return }
        let f = cheatField
        rect(f.minX,f.minY,f.width,f.height,Tac.panel,0.94)
        outline(f,devMode ? Tac.green : Tac.text)
        text(cheatEntry,f.minX+8,f.minY+4,12,devMode ? Tac.green : Tac.bright,.semibold,true)
        if blink { rect(f.minX+9+textWidth(cheatEntry,12,.semibold,true),f.minY+5,1.5,f.height-10,Tac.text) }
    }
    /// Persistent dev mode tag beside the cheat box and a banner that fades after activation.
    func drawDevMode(_ t: Double) {
        guard devMode else { return }
        let x = cheatOpen ? cheatField.maxX+12 : cheatButton.maxX+10
        text("◆ DEV MODE · INFINITE CREDITS · NO COOLDOWNS",x,cheatButton.minY+5,10,Tac.green,.heavy,true)
        let age = t-devModeSince
        guard age < 3.5 else { return }
        let a = age < 2.5 ? 1 : 1-(age-2.5)
        let r = NSRect(x:420,y:380,width:600,height:120)
        rect(0,0,1440,900,Tac.green,0.08*a*max(0,1-age/0.6))
        panel(r,Tac.raised,0.97*a,Tac.green,14)
        brackets(r.insetBy(dx:-8,dy:-8),Tac.green,16,a,2)
        let title = "DEV MODE ENABLED", sub = "INFINITE CREDITS · NO COOLDOWNS · ALL LEVELS UNLOCKED"
        text(title,r.midX-textWidth(title,34,.heavy,true)/2,r.minY+24,34,Tac.green,.heavy,true,a)
        text(sub,r.midX-textWidth(sub,12,.bold,true)/2,r.minY+76,12,Tac.bright,.bold,true,a)
    }
    func toggleCheatBox() {
        cheatOpen.toggle(); cheatEntry = ""
        sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    /// Handles a key typed while the cheat box is open.
    func cheatKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: cheatOpen = false; cheatEntry = ""
        case 51: if !cheatEntry.isEmpty { cheatEntry.removeLast() }
        case 36, 76: cheatEntry = ""
        default:
            let typed = (event.characters ?? "").filter { $0.isLetter || $0.isNumber }
            guard !typed.isEmpty, cheatEntry.count < 15 else { return }
            cheatType(String(typed.prefix(15-cheatEntry.count)))
        }
        needsDisplay = true
    }
    func cheatType(_ typed: String) {
        cheatEntry += typed
        if !devMode && cheatEntry.lowercased().contains("dev") {
            devMode = true; devModeSince = ProcessInfo.processInfo.systemUptime
            sound.play(SoundEvent(cue:.deploy))
        }
    }
    let bankFrame = NSRect(x:96,y:572,width:584,height:206)
    enum BankControl: CaseIterable { case less, more, max }
    func bankButton(_ c: BankControl) -> NSRect {
        let r = bankFrame
        switch c {
        case .less: return NSRect(x:r.minX+22,y:r.minY+118,width:40,height:36)
        case .more: return NSRect(x:r.minX+210,y:r.minY+118,width:40,height:36)
        case .max: return NSRect(x:r.minX+262,y:r.minY+118,width:64,height:36)
        }
    }
    func adjustWithdrawal(_ c: BankControl) {
        switch c {
        case .less: withdrawal -= Self.withdrawalStep
        case .more: withdrawal += Self.withdrawalStep
        case .max: withdrawal = world.bank
        }
        withdrawal = max(0,min(world.bank,withdrawal))
        sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    /// Lobby bank: the saved balance and how much of it to bring into the next operation.
    func drawBank() {
        let r = bankFrame
        withdrawal = max(0,min(world.bank,withdrawal))
        panel(r,Tac.raised,0.94,Tac.rule,14)
        rect(r.minX,r.minY,4,r.height,Tac.amber)
        text("▸ BANK",r.minX+22,r.minY+14,10,Tac.amber,.heavy,true)
        text("UNSPENT CREDITS ARE BANKED WHEN YOU EXTRACT",r.maxX-310,r.minY+14,9,Tac.dim,.medium,true)
        text(cr(world.bank),r.minX+22,r.minY+32,26,world.bank > 0 ? Tac.bright : Tac.dim,.heavy,true)
        rect(r.minX+22,r.minY+76,r.width-44,1,Tac.rule,0.6)
        text("BRING INTO NEXT OPERATION",r.minX+22,r.minY+90,9,Tac.dim,.bold,true)
        for c in BankControl.allCases {
            let b = bankButton(c), enabled = world.bank > 0
            let hovered = enabled && isHovering && b.contains(NSPoint(x:pointer.x,y:pointer.y))
            rect(b.minX,b.minY,b.width,b.height,hovered ? Tac.hover : Tac.panel)
            line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],hovered ? Tac.green : Tac.rule)
            let label = c == .less ? "−" : c == .more ? "+" : "MAX"
            let size = c == .max ? 11.0 : 18.0
            text(label,b.midX-textWidth(label,size,.heavy,true)/2,b.midY-size*0.62,size,enabled ? (hovered ? Tac.green : Tac.text) : Tac.rule,.heavy,true)
        }
        let amount = cr(withdrawal)
        text(amount,r.minX+136-textWidth(amount,16,.semibold,true)/2,r.minY+125,16,withdrawal > 0 ? Tac.amber : Tac.dim,.semibold,true)
        let arrives = World.delivered(withdrawal)
        text("ARRIVES AS",r.minX+350,r.minY+116,9,Tac.dim,.bold,true)
        text("+\(cr(arrives))",r.minX+350,r.minY+130,16,withdrawal > 0 ? Tac.green : Tac.dim,.semibold,true)
        text("\(Int(World.withdrawalLoss*100))% OF ANY WITHDRAWAL IS LOST IN TRANSIT · ADDED TO THE OPERATION'S GRANT",r.minX+22,r.minY+172,9,Tac.dim,.medium,true)
    }
    /// Animated surveillance radar for the main menu.
    func drawRadar(_ t:Double) {
        let (cx,cy,r) = (1046.0,470.0,196.0)
        let focus = levels[hoveredLevel ?? nextLevel]
        text("AO \(focus.operation.replacingOccurrences(of:"OPERATION ",with:""))  //  \(focus.grid)",cx-r,cy-r-44,10,Tac.amber,.bold,true)
        text("LIVE",cx+r-34,cy-r-44,10,Tac.green,.bold,true)
        circle(cx,cy,r,Tac.panel,0.85)
        for k in 1...4 {
            let rr = r*Double(k)/4
            let ring = NSBezierPath(ovalIn:NSRect(x:cx-rr,y:cy-rr,width:rr*2,height:rr*2))
            ring.lineWidth = k == 4 ? 1.5 : 1; color(Tac.green,k == 4 ? 0.55 : 0.18).setStroke(); ring.stroke()
        }
        line([CGPoint(x:cx-r,y:cy),CGPoint(x:cx+r,y:cy)],Tac.green,1,0.18)
        line([CGPoint(x:cx,y:cy-r),CGPoint(x:cx,y:cy+r)],Tac.green,1,0.18)
        for d in stride(from:0,to:360,by:10) {
            let a = Double(d) * .pi/180, inner = r - (d % 30 == 0 ? 12 : 6)
            line([CGPoint(x:cx+cos(a)*inner,y:cy+sin(a)*inner),CGPoint(x:cx+cos(a)*r,y:cy+sin(a)*r)],Tac.green,1,0.5)
        }
        for (label,a) in [("000",-Double.pi/2),("090",0.0),("180",Double.pi/2),("270",Double.pi)] {
            text(label,cx+cos(a)*(r+20)-11,cy+sin(a)*(r+20)-7,9,Tac.dim,.medium,true)
        }
        // Sweep with a fading phosphor trail.
        let sweep = (t*1.3).truncatingRemainder(dividingBy:2 * .pi)
        for k in 0..<28 {
            let a0 = sweep - Double(k)*0.035, a1 = a0 - 0.035
            polygon([CGPoint(x:cx,y:cy),CGPoint(x:cx+cos(a0)*r,y:cy+sin(a0)*r),CGPoint(x:cx+cos(a1)*r,y:cy+sin(a1)*r)],Tac.green,0.22*(1-Double(k)/28))
        }
        line([CGPoint(x:cx,y:cy),CGPoint(x:cx+cos(sweep)*r,y:cy+sin(sweep)*r)],Tac.green,2,0.9)
        for (n,(a,d)) in [(0.45,0.62),(1.9,0.82),(2.25,0.4),(3.7,0.7),(5.1,0.5)].enumerated() {
            var since = (sweep - a).truncatingRemainder(dividingBy:2 * .pi); if since < 0 { since += 2 * .pi }
            let glow = max(0,1 - since/3.2)
            guard glow > 0.02 else { continue }
            let (bx,by) = (cx+cos(a)*r*d,cy+sin(a)*r*d)
            circle(bx,by,7,n == 3 ? Tac.amber : Tac.green,0.18*glow)
            circle(bx,by,3,n == 3 ? Tac.amber : Tac.green,glow)
            if glow > 0.35 { text(n == 3 ? "OBJ" : String(format:"C%02d",n+1),bx+8,by-14,9,n == 3 ? Tac.amber : Tac.green,.bold,true) }
        }
        circle(cx,cy,3,Tac.amber)
        let readouts = [("RANGE","2.4 KM"),("WIND","12 KT NW"),("VIS","LOW / RAIN")]
        for (i,item) in readouts.enumerated() {
            let x = cx-r+Double(i)*136
            text(item.0,x,cy+r+40,9,Tac.dim,.bold,true)
            text(item.1,x,cy+r+56,13,Tac.text,.medium,true)
        }
    }
    func startLevel(_ i:Int) {
        guard levels.indices.contains(i) else { return }
        guard world.unlocked(i) else {
            sound.play(SoundEvent(cue:.cease)); return
        }
        // A different map size invalidates every cached tile and section image.
        World.select(i); tiles = [:]; chunkImages = [:]; minimap = nil
        briefingSince = ProcessInfo.processInfo.systemUptime
        sound.stopEffects(); world.reset(); closeDeploy()
        if withdrawal > 0 && !devMode {
            let arrived = world.withdraw(withdrawal)
            world.status = "\(cr(withdrawal)) WITHDRAWN FROM THE BANK · \(cr(arrived)) ARRIVED · PRESS \(k(.troops)) TO DEPLOY TROOPS"
        }
        withdrawal = 0
        sound.play(SoundEvent(cue:.select))
        inMenu = false; previous = ProcessInfo.processInfo.systemUptime
        resetCamera()
        needsDisplay = true
    }
    /// Title card naming the operation for a few seconds after it starts.
    func drawBriefing() {
        let age = ProcessInfo.processInfo.systemUptime-briefingSince
        guard age < 4.5 else { return }
        let a = age < 3.5 ? min(1,age/0.25) : 1-(age-3.5)
        let spec = World.spec, r = NSRect(x:440,y:196,width:560,height:118)
        panel(r,Tac.panel,0.9*a,Tac.amber,14)
        brackets(r.insetBy(dx:-7,dy:-7),Tac.amber,14,a,2)
        rect(r.minX,r.minY,r.width,4,Tac.amber,a)
        let head = String(format:"OP-%02d  ·  ",World.level+1)+spec.operation
        let detail = "\(world.objectives.count) HVTs  ·  GOAL \(pts(spec.requirement))  ·  \(String(format:"%.1f",Double(World.columns)*World.cell/1000)) KM FRONT"
        text(head,r.midX-textWidth(head,11,.bold,true)/2,r.minY+18,11,Tac.amber,.bold,true,a)
        text(spec.name,r.midX-textWidth(spec.name,34,.heavy,true)/2,r.minY+36,34,Tac.bright,.heavy,true,a)
        text(detail,r.midX-textWidth(detail,10,.medium,true)/2,r.minY+86,10,Tac.text,.medium,true,a)
    }
    func escButton(_ i:Int) -> NSRect { NSRect(x:524,y:296+Double(i)*66,width:392,height:56) }
    /// Volume steppers on the settings page's volume row, either side of the level bar.
    func volumeButton(_ up:Bool) -> NSRect { let r = escButton(1); return NSRect(x:r.maxX-(up ? 46 : 196),y:r.minY+12,width:32,height:32) }
    var volumeBar: NSRect { let r = escButton(1); return NSRect(x:r.maxX-158,y:r.minY+22,width:106,height:12) }
    /// Buttons on the exit confirmation: main menu, quit, cancel.
    func exitButton(_ i:Int) -> NSRect { NSRect(x:548+Double(i)*118,y:448,width:108,height:56) }
    var fullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    func escHovered(_ r:NSRect) -> Bool { isHovering && r.contains(NSPoint(x:pointer.x,y:pointer.y)) }
    /// One pause menu row: hotkey, title and a one-line hint.
    func escRow(_ r:NSRect,_ key:String,_ title:String,_ detail:String,_ hovered:Bool,_ titleColor:UInt32 = Tac.bright) {
        let accent = hovered ? Tac.green : Tac.amber
        panel(r,hovered ? Tac.hover : Tac.raised,1,hovered ? accent : Tac.rule,8)
        rect(r.minX,r.minY,3,r.height,accent)
        if hovered { brackets(r.insetBy(dx:-5,dy:-5),accent,9) }
        text(key,r.minX+16,r.minY+19,11,hovered ? accent : Tac.dim,.bold,true)
        text(title,r.minX+58,r.minY+9,16,titleColor,.heavy,true)
        text(detail,r.minX+58,r.minY+34,9,Tac.dim,.medium,true)
    }
    /// An ON / OFF switch at the right of a settings row.
    func escSwitch(_ r:NSRect,_ on:Bool) {
        let s = NSRect(x:r.maxX-78,y:r.minY+14,width:62,height:28)
        rect(s.minX,s.minY,s.width,s.height,0x000000,0.35)
        line([CGPoint(x:s.minX,y:s.minY),CGPoint(x:s.maxX,y:s.minY),CGPoint(x:s.maxX,y:s.maxY),CGPoint(x:s.minX,y:s.maxY),CGPoint(x:s.minX,y:s.minY)],on ? Tac.green : Tac.rule)
        rect(on ? s.midX : s.minX,s.minY,s.width/2,s.height,on ? Tac.green : Tac.rule,on ? 0.9 : 0.8)
        text(on ? "ON" : "OFF",on ? s.minX+6 : s.midX+4,s.minY+8,10,on ? Tac.green : Tac.dim,.heavy,true)
    }
    func drawEscMenu() {
        let blink = Int(ProcessInfo.processInfo.systemUptime*2) % 2 == 0
        rect(0,0,1440,900,0x070a07,0.88)
        for y in stride(from:0.0,to:900,by:3) { rect(0,y,1440,1,0x000000,0.12) }
        let frame = NSRect(x:500,y:160,width:440,height:470)
        panel(frame,Tac.panel,0.97,Tac.rule,16)
        brackets(frame.insetBy(dx:-9,dy:-9),Tac.amber,18,0.85,2)
        rect(500,160,424,28,Tac.amber,0.9)
        text(escPage == .settings ? "■ SETTINGS" : "■ SIMULATION HALTED",514,167,10,0x1a1408,.heavy,true)
        let secs = Int(world.elapsed)
        text(String(format:"T+ %02d:%02d",secs/60,secs%60),850,167,10,0x1a1408,.heavy,true)
        rect(524,212,5,escPage == .settings ? 30 : 38,Tac.amber)
        text(escPage == .settings ? "SETTINGS" : "PAUSED",540,208,30,Tac.bright,.heavy,true)
        if escPage == .settings { drawSettingsTabs() }
        else { text("AWAITING ORDERS, COMMANDER" + (blink ? "_" : ""),542,256,10,Tac.dim,.medium,true) }
        rect(524,280,392,1,Tac.rule)
        if escPage == .settings {
            if settingsTab == .controls { drawControls() } else { drawSettingRows("RETURN TO THE PAUSE MENU") }
        } else {
            for (i,option) in escOptions.enumerated() {
                let r = escButton(i), hovered = escHovered(r) && escPage == .main
                escRow(r,escKeys[i],option.0,option.1,hovered)
                if hovered { text("▸",r.maxX-28,r.minY+16,16,Tac.green,.bold,true) }
            }
        }
        rect(524,580,392,1,Tac.rule,0.6)
        if escPage == .settings && settingsTab == .controls { drawControlsFooter() }
        else { text(escPage == .settings ? "SETTINGS ARE SAVED AUTOMATICALLY   //   [TAB] CONTROLS" : "[\(k(.guide))] FIELD GUIDE   //   [F] FULL SCREEN",526,594,9,Tac.dim,.medium,true) }
        if escPage == .exit { drawExitConfirm() }
    }
    /// Sound, volume and full screen rows and a back row, shared by the pause menu and the lobby settings.
    func drawSettingRows(_ back:String) {
        let soundOn = sound.available && !sound.muted
        let r0 = escButton(0)
        escRow(r0,"[M]","SOUND",!sound.available ? "NO AUDIO DEVICE" : soundOn ? "CLICK TO MUTE" : "CLICK TO TURN SOUND ON",escHovered(r0) && sound.available)
        escSwitch(r0,soundOn)
        let r1 = escButton(1)
        escRow(r1,"[−/+]","VOLUME","\(Int((sound.volume*100).rounded()))%",false,soundOn ? Tac.bright : Tac.dim)
        for up in [false,true] {
            let b = volumeButton(up), over = escHovered(b) && sound.available
            rect(b.minX,b.minY,b.width,b.height,over ? Tac.hover : 0x000000,over ? 1 : 0.35)
            line([CGPoint(x:b.minX,y:b.minY),CGPoint(x:b.maxX,y:b.minY),CGPoint(x:b.maxX,y:b.maxY),CGPoint(x:b.minX,y:b.maxY),CGPoint(x:b.minX,y:b.minY)],over ? Tac.green : Tac.rule)
            text(up ? "+" : "−",b.minX+10,b.minY+6,15,over ? Tac.green : Tac.text,.bold,true)
        }
        let bar = volumeBar
        rect(bar.minX,bar.minY,bar.width,bar.height,0x000000,0.35)
        rect(bar.minX,bar.minY,bar.width*Double(sound.volume),bar.height,soundOn ? Tac.green : Tac.rule)
        let r2 = escButton(2)
        escRow(r2,"[F]","FULL SCREEN",fullScreen ? "CLICK FOR A WINDOW" : "CLICK TO FILL THE SCREEN",escHovered(r2))
        escSwitch(r2,fullScreen)
        let r3 = escButton(3), over = escHovered(r3)
        escRow(r3,"[ESC]","BACK",back,over)
        if over { text("◂",r3.maxX-28,r3.minY+16,16,Tac.green,.bold,true) }
    }
    /// The pop-up asking where to go when leaving the operation.
    func drawExitConfirm() {
        rect(0,0,1440,900,0x000000,0.55)
        let box = NSRect(x:530,y:356,width:380,height:168)
        panel(box,Tac.panel,1,Tac.red,12)
        brackets(box.insetBy(dx:-7,dy:-7),Tac.red,14,0.9,2)
        rect(box.minX+18,box.minY+22,4,30,Tac.red)
        text("LEAVE THE OPERATION?",box.minX+32,box.minY+20,20,Tac.bright,.heavy,true)
        text("PROGRESS ON THIS MAP WILL BE LOST",box.minX+34,box.minY+50,9,Tac.dim,.medium,true)
        let options = [("MAIN MENU","[M]",Tac.amber),("QUIT GAME","[Q]",Tac.red),("CANCEL","[ESC]",Tac.dim)]
        for (i,o) in options.enumerated() {
            let b = exitButton(i), hovered = escHovered(b)
            panel(b,hovered ? Tac.hover : Tac.raised,1,hovered ? o.2 : Tac.rule,6)
            rect(b.minX,b.minY,3,b.height,o.2)
            if hovered { brackets(b.insetBy(dx:-4,dy:-4),o.2,7) }
            text(o.0,b.minX+12,b.minY+12,12,hovered && i < 2 ? o.2 : Tac.bright,.heavy,true)
            text(o.1,b.minX+12,b.minY+34,9,Tac.dim,.bold,true)
        }
    }
    func openEscMenu() {
        pausedBeforeEscMenu = world.paused
        world.paused = true; escMenu = true; escPage = .main
        sound.sync(paused:true,active:NSApp.isActive)
        sound.play(SoundEvent(cue:.pause))
    }
    func closeEscMenu() {
        escMenu = false; rebinding = nil; world.paused = pausedBeforeEscMenu
        previous = ProcessInfo.processInfo.systemUptime
        sound.play(SoundEvent(cue:.pause))
    }
    func showEscPage(_ page:EscPage) {
        escPage = page; rebinding = nil
        if page == .settings { settingsTab = .general }
        sound.play(SoundEvent(cue:.select)); needsDisplay = true
    }
    func chooseEscOption(_ i:Int) {
        switch i {
        case 0: closeEscMenu()
        case 1:
            escMenu = false; resetMap()
            world.paused = false; previous = ProcessInfo.processInfo.systemUptime
            sound.sync(paused:false,active:NSApp.isActive)
        case 2: showEscPage(.settings)
        case 3: showEscPage(.exit)
        default: break
        }
        needsDisplay = true
    }
    func chooseSetting(_ i:Int) {
        switch i {
        case 0: if sound.available { sound.toggleMute() }
        case 2: window?.toggleFullScreen(nil)
        case 3: if inMenu { closeLobbySettings() } else { showEscPage(.main) }
        default: break
        }
        needsDisplay = true
    }
    func chooseExit(_ i:Int) {
        switch i {
        case 0:
            escMenu = false; sound.stopEffects(); world.reset(); closeDeploy()
            inMenu = true; help = true; resetCamera()
            sound.play(SoundEvent(cue:.select))
        case 1: NSApp.terminate(nil)
        default: showEscPage(.main)
        }
        needsDisplay = true
    }
    /// Clicks on the pause menu, routed by page.
    func escMouseDown(_ p:NSPoint) {
        switch escPage {
        case .main:
            if let i = escOptions.indices.first(where:{ escButton($0).contains(p) }) { chooseEscOption(i) }
        case .settings:
            if let tab = settingsTabs.first(where:{ settingsTabRect($0).contains(p) }) { showSettingsTab(tab) }
            else if settingsTab == .controls { controlsMouseDown(p) }
            else { settingsMouseDown(p) }
        case .exit:
            if let i = (0..<3).first(where:{ exitButton($0).contains(p) }) { chooseExit(i) }
        }
    }
    /// Clicks on the settings rows drawn by `drawSettingRows`.
    func settingsMouseDown(_ p:NSPoint) {
        guard !(sound.available && escButton(1).contains(p)) else {
            if let up = [false,true].first(where:{ volumeButton($0).contains(p) }) { sound.adjustVolume(up ? 0.1 : -0.1) }
            else if volumeBar.insetBy(dx:-4,dy:-10).contains(p) {
                let target = Float(((p.x-volumeBar.minX)/volumeBar.width*10).rounded()/10)
                sound.adjustVolume(max(0,min(1,target))-sound.volume)
            }
            return
        }
        if let i = (0..<4).first(where:{ escButton($0).contains(p) }) { chooseSetting(i) }
    }
    func escKeyDown(_ key:String?,_ event:NSEvent,_ command:Bool) {
        if rebinding != nil && !command { rebindKeyDown(event); return }
        if key == "f" { window?.toggleFullScreen(nil); return }
        switch escPage {
        case .main:
            switch key {
            case "\u{1b}", "\r", "\u{3}": chooseEscOption(0)
            case _ where event.keyCode == binds.key(.guide) || event.keyCode == Self.f1Key: closeEscMenu(); help = true
            case "r": chooseEscOption(1)
            case "s": chooseEscOption(2)
            case "q" where !command: chooseEscOption(3)
            case "m": sound.toggleMute()
            default: super.keyDown(with:event)
            }
        case .settings:
            if event.keyCode == Self.tabKey { nextSettingsTab(); return }
            switch key {
            case "\u{1b}", "\u{7f}", "\r", "\u{3}": showEscPage(.main)
            case "m" where settingsTab == .general: chooseSetting(0)
            case "[", "-": sound.adjustVolume(-0.1)
            case "]", "=", "+": sound.adjustVolume(0.1)
            default: super.keyDown(with:event)
            }
        case .exit:
            switch key {
            case "\u{1b}": chooseExit(2)
            case "m", "\r", "\u{3}": chooseExit(0)
            case "q" where !command: chooseExit(1)
            default: super.keyDown(with:event)
            }
        }
    }
    /// A labelled readout cell in the top bar.
    func readout(_ label:String,_ value:String,_ x:Double,_ width:Double,_ c:UInt32) {
        rect(x,22,width,62,0x000000,0.25)
        line([CGPoint(x:x,y:22),CGPoint(x:x+width,y:22)],Tac.rule)
        rect(x,22,2,10,c)
        text(label,x+10,27,9,Tac.dim,.bold,true)
        text(value,x+10,44,24,c,.semibold,true)
    }
    /// Square icon buttons at the left of the top bar: the pause menu and the field guide.
    let menuButtonFrame = NSRect(x:24,y:24,width:56,height:56)
    let guideButtonFrame = NSRect(x:88,y:24,width:56,height:56)
    func iconButton(_ r: NSRect,_ key: String,_ on: Bool = false,_ glyph: (NSRect,UInt32) -> Void) {
        let hovered = isHovering && r.contains(NSPoint(x:pointer.x,y:pointer.y))
        let c = hovered || on ? Tac.green : Tac.bright
        panel(r,hovered || on ? Tac.hover : Tac.raised,1,hovered || on ? Tac.green : Tac.rule,8)
        glyph(r,c)
        text(key,r.midX-textWidth(key,9,.bold,true)/2,r.minY+39,9,Tac.dim,.bold,true)
    }
    /// The dock keeps only the actions used constantly; everything else lives in menus.
    enum DockAction: CaseIterable { case deploy, selectAll, cease, extract }
    func dockFrame(_ a: DockAction) -> NSRect {
        switch a {
        case .deploy: return NSRect(x:30,y:827,width:340,height:58)
        case .selectAll: return NSRect(x:560,y:827,width:150,height:58)
        case .cease: return NSRect(x:722,y:827,width:150,height:58)
        case .extract: return NSRect(x:1110,y:827,width:300,height:58)
        }
    }
    func drawHUD() {
        rect(0,0,1440,104,Tac.panel); rect(0,103,1440,1,Tac.rule)
        for x in stride(from:0.0,to:1440,by:12) { rect(x,98,1,x.truncatingRemainder(dividingBy:60) == 0 ? 5 : 2,Tac.rule) }
        iconButton(menuButtonFrame,"ESC") { r,c in for k in 0..<3 { self.rect(r.minX+16,r.minY+13+Double(k)*7,24,3,c) } }
        iconButton(guideButtonFrame,"TAB",help) { r,c in self.text("?",r.minX+20,r.minY+6,22,c,.heavy,true) }
        let t = Int(world.elapsed)
        text(String(format:"OP-%02d · OPERATION",World.level+1),164,27,9,Tac.dim,.bold,true)
        let op = World.spec.operation.replacingOccurrences(of:"OPERATION ",with:"")
        text(op,164,42,min(24,24*126/textWidth(op,24,.heavy,true)),Tac.bright,.heavy,true)
        text(String(format:"T+%02d:%02d",t/60,t%60),164,74,9,Tac.dim,.medium,true)
        // Troops, with selection in the label and ammo trouble beside the count.
        let selected = world.soldiers.filter{$0.selected}.count
        readout(selected > 0 ? "TROOPS · \(selected) SELECTED" : "TROOPS","\(world.soldiers.count)",300,220,Tac.green)
        let low = world.soldiers.filter{$0.lowAmmo}.count, dry = world.soldiers.filter{$0.outOfAmmo}.count
        var tagY = 46.0
        if dry > 0 { text("■ \(dry) NO AMMO",420,tagY,9,Tac.red,.bold,true); tagY += 16 }
        if low > 0 { text("■ \(low) LOW AMMO",420,tagY,9,Tac.amber,.bold,true) }
        // Credits buy troops and support; points are earned by destruction and needed to extract.
        readout("CREDITS",creditsText,536,180,Tac.amber)
        let ready = world.missionReady
        readout("POINTS",pts(world.points),732,344,ready ? Tac.green : Tac.text)
        let goal = ready ? "GOAL MET · [X] EXTRACT" : "GOAL \(pts(World.requirement))"
        text(goal,1064-textWidth(goal,10,.bold,true),30,10,ready ? Tac.green : Tac.dim,.bold,true)
        let progress = min(1,max(0,Double(world.points)/Double(World.requirement)))
        rect(742,77,322,3,Tac.rule); rect(742,77,322*progress,3,ready ? Tac.green : Tac.text)
        drawTempo()
        if !sound.available || sound.muted {
            let r = muteTagFrame
            rect(r.minX,r.minY,r.width,r.height,Tac.amber,0.12)
            text(sound.available ? "MUTED" : "NO AUDIO",r.minX+6,r.minY+3,9,Tac.amber,.bold,true)
        }
        // Command dock.
        rect(0,808,1440,92,0x0b0f0b); rect(0,808,1440,1,Tac.rule)
        let deploy = dockFrame(.deploy)
        let deploySub: String
        if placingTroops { deploySub = "CLICK THE GREEN ZONE · RMB/ESC DONE" }
        else if placing != nil { deploySub = "FROM \(world.supportSide.map{ $0 > 0 ? "WEST" : "EAST" } ?? "NEAR EDGE") · \(k(.support))/\(k(.troops)) SIDE · ESC DONE" }
        else if low+dry > 0 { deploySub = "AMMO LOW · [\(k(.support))] CALL A SUPPLY DROP" }
        else { deploySub = "TROOPS & SUPPORT" }
        button(placingName.map{"PLACING ▸ \($0)"} ?? "+ DEPLOY",deploySub,deploy.minX,deploy.width,true,k(.troops))
        button(allSelected ? "DESELECT ALL" : "SELECT ALL",allSelected ? "CLEAR SELECTION" : "COMMAND PLATOON",dockFrame(.selectAll).minX,dockFrame(.selectAll).width,false,k(.selectAll))
        button("CEASE FIRE","HOLD POSITION",dockFrame(.cease).minX,dockFrame(.cease).width,false,k(.cease))
        let short = World.requirement-world.points
        button("EXTRACT",world.missionReady ? "MISSION READY" : "\(pts(short)) TO GO",dockFrame(.extract).minX,dockFrame(.extract).width,world.missionReady,k(.extract))
    }
    let muteTagFrame = NSRect(x:1360,y:46,width:60,height:18)
    /// Pause and game speed in the top bar: a pause switch then 0.25× / 1× / 2× / 4×.
    /// Cell 0 is pause; cells 1-4 are the speeds.
    func tempoCell(_ i:Int) -> NSRect {
        i == 0 ? NSRect(x:1080,y:44,width:46,height:34) : NSRect(x:1132+Double(i-1)*57,y:44,width:54,height:34)
    }
    /// Green at real time; cyan in slow motion; amber once the clock runs fast, red at full speed.
    func tempoColor(_ speed:Double) -> UInt32 { speed >= 4 ? Tac.red : speed > 1 ? Tac.amber : speed < 1 ? Tac.cyan : Tac.green }
    func speedLabel(_ speed:Double) -> String { speed < 1 ? "0.25×" : "\(Int(speed))×" }
    func drawTempo() {
        let paused = world.paused, active = paused ? Tac.amber : tempoColor(world.speed)
        let blink = paused || Int(world.elapsed*2) % 2 == 0
        circle(1084,32,3.5,active,blink ? 1 : 0.25)
        let mode = world.speed < 1 ? "SLOW MO 0.25×" : world.speed == 1 ? "LIVE · REAL TIME" : world.speed == 2 ? "FAST FWD 2×" : "MAX FWD 4×"
        text(paused ? "HOLD · PAUSED" : mode,1094,25,9,active,.bold,true)
        func frame(_ cell: NSRect,_ on: Bool,_ c: UInt32,_ over: Bool) {
            rect(cell.minX,cell.minY,cell.width,cell.height,on ? c : 0x000000,on ? 0.2 : (over ? 0.15 : 0.35))
            line([CGPoint(x:cell.minX,y:cell.minY),CGPoint(x:cell.maxX,y:cell.minY),CGPoint(x:cell.maxX,y:cell.maxY),CGPoint(x:cell.minX,y:cell.maxY),CGPoint(x:cell.minX,y:cell.minY)],on ? c : (over ? Tac.dim : Tac.rule),1)
            if on { brackets(cell.insetBy(dx:-2,dy:-2),c,4,1,1) }
        }
        let pause = tempoCell(0), overPause = isHovering && pause.contains(NSPoint(x:pointer.x,y:pointer.y))
        frame(pause,paused,Tac.amber,overPause)
        let pc = paused ? Tac.amber : (overPause ? Tac.bright : Tac.text)
        if paused {
            // Shows play while held: clicking resumes.
            polygon([CGPoint(x:pause.midX-5,y:pause.midY-8),CGPoint(x:pause.midX+8,y:pause.midY),CGPoint(x:pause.midX-5,y:pause.midY+8)],pc)
        } else { rect(pause.midX-7,pause.midY-8,5,16,pc); rect(pause.midX+2,pause.midY-8,5,16,pc) }
        for (i,speed) in World.speeds.enumerated() {
            let cell = tempoCell(i+1), on = speed == world.speed, c = tempoColor(speed)
            let over = isHovering && cell.contains(NSPoint(x:pointer.x,y:pointer.y))
            frame(cell,on && !paused,c,over)
            // Chevrons light up with speed, one more per doubling, like throttle detents.
            for k in 0..<3 { text("›",cell.minX+6+Double(k)*4,cell.minY+9,10,k < i ? (on ? c : Tac.dim) : Tac.rule,.heavy,true) }
            text(speedLabel(speed),cell.minX+20,cell.minY+9,11,on ? Tac.bright : Tac.dim,.bold,true)
        }
        let tempoKeys = "\(k(.pause)) · \(k(.speed))"
        text(tempoKeys,tempoCell(World.speeds.count).maxX-textWidth(tempoKeys,8,.bold,true),84,8,Tac.dim,.bold,true)
    }
    func setSpeed(_ speed:Double) {
        if world.paused { togglePause() }
        guard speed != world.speed else { return }
        world.speed = speed; tempoChanged()
    }
    func cycleSpeed() { world.cycleSpeed(); tempoChanged() }
    func tempoChanged() {
        sound.play(SoundEvent(cue:.select))
        let s = speedLabel(world.speed), key = k(.speed)
        world.status = world.speed == 1 ? "TEMPO 1× · REAL TIME" : world.speed < 1 ? "TEMPO \(s) · SLOW MOTION · [\(key)] TO CHANGE" : "TEMPO \(s) · SIMULATION RUNNING FAST · [\(key)] TO CHANGE"
    }
    /// Red brackets around intact high-value targets and floating score popups.
    func drawObjectiveMarkers() {
        let c = World.cell
        for o in world.objectives {
            let a = toScreen(Vec(x:Double(o.x0)*c,y:Double(o.y0)*c+World.top))
            let b = toScreen(Vec(x:Double(o.x1)*c,y:Double(o.y1)*c+World.top))
            let r = NSRect(x:a.x,y:a.y,width:b.x-a.x,height:b.y-a.y).insetBy(dx:-4,dy:-4)
            guard r.maxX > 0 && r.minX < 1440 && r.maxY > 104 && r.minY < 808 else { continue }
            let tint = o.destroyed ? Tac.dim : Tac.red
            brackets(r,tint,min(14,r.width/3),o.destroyed ? 0.45 : 0.85,1.5)
            let ly = max(108,r.minY-19)
            text(o.destroyed ? "✕ \(o.name)" : "HVT · \(o.name) +\(pts(o.bonus))",r.minX,ly,9,tint,.bold,true)
            if !o.destroyed { damageBar(r.minX,ly+13,90,o) }
        }
        for p in world.popups {
            let s = toScreen(p.position)
            guard s.x > -40 && s.x < 1480 && s.y > 104 && s.y < 808 else { continue }
            let alpha = min(1,p.life*2)
            let font = NSFont.monospacedSystemFont(ofSize:p.major ? 16 : 10,weight:.heavy)
            ("+\(pts(p.points))" as NSString).draw(at:NSPoint(x:s.x-(p.major ? 30 : 12),y:s.y-10),withAttributes:[.font:font,.foregroundColor:color(p.major ? Tac.red : Tac.amber,alpha)])
            if p.major { text("HVT DESTROYED",s.x-30,s.y+10,9,Tac.red,.bold,true) }
        }
    }
    /// How close an HVT is to destruction: full when its bonus pays out.
    func damageBar(_ x: Double,_ y: Double,_ w: Double,_ o: Objective) {
        rect(x,y,w,3,Tac.rule); rect(x,y,w*min(1,o.damage/World.objectiveThreshold),3,Tac.red)
    }
    /// Objective list under the minimap. Collapsed it is one header line with a tally;
    /// clicking it (or O) lists each HVT's damage and bonus.
    var targetsHeader: NSRect { NSRect(x:1104,y:214,width:328,height:22) }
    func drawObjectives() {
        let h = targetsHeader, done = world.objectives.filter{$0.destroyed}.count
        let rows = showTargets ? Double(world.objectives.count) : 0
        let r = NSRect(x:h.minX,y:h.minY,width:h.width,height:h.height+(showTargets ? 8+rows*18 : 0))
        let hovered = isHovering && h.contains(NSPoint(x:pointer.x,y:pointer.y))
        panel(r,hovered ? Tac.hover : Tac.panel,0.9); rect(h.minX,h.minY,h.width,h.height,Tac.red,0.14); rect(h.minX,h.minY,3,r.height,Tac.red)
        text("▲ HIGH-VALUE TARGETS",h.minX+12,h.minY+5,10,Tac.red,.bold,true)
        text("\(done)/\(world.objectives.count) DOWN  \(showTargets ? "▴" : "▾") [\(k(.targets))]",h.maxX-128,h.minY+5,9,hovered ? Tac.bright : Tac.text,.bold,true)
        guard showTargets else { return }
        for (i,o) in world.objectives.enumerated() {
            let ry = h.maxY+6+Double(i)*18
            text(o.destroyed ? "✕" : "◆",h.minX+12,ry,9,o.destroyed ? Tac.green : Tac.red,.bold,true)
            text(o.name,h.minX+28,ry,9,o.destroyed ? Tac.dim : Tac.text,.semibold,true)
            if !o.destroyed { damageBar(h.minX+178,ry+5,50,o) }
            text(o.destroyed ? "PAID ✓" : "+\(pts(o.bonus))",h.maxX-96,ry,9,o.destroyed ? Tac.green : Tac.amber,.medium,true)
        }
    }
    /// The latest status message, centred above the dock. It fades out after a few seconds
    /// unless it is guidance the player still needs (first deployment, placement).
    func drawStatusToast() {
        let now = ProcessInfo.processInfo.systemUptime
        if world.status != shownStatus { shownStatus = world.status; statusSince = now }
        let sticky = placing != nil || world.soldiers.isEmpty
        let a = sticky ? 1 : max(0,min(1,6-(now-statusSince)))
        guard a > 0, !shownStatus.isEmpty else { return }
        let w = textWidth(shownStatus,10,.medium,true)+36
        let r = NSRect(x:720-w/2,y:772,width:w,height:24)
        rect(r.minX,r.minY,r.width,r.height,Tac.panel,0.9*a)
        rect(r.minX,r.minY,3,r.height,Tac.green,a)
        text("›",r.minX+12,r.minY+5,10,Tac.green,.heavy,true,a)
        text(shownStatus,r.minX+24,r.minY+5,10,Tac.green,.medium,true,a)
    }
    // MARK: Requisition
    func closeDeploy() { deployMenu = false; placing = nil }
    var placingTroops: Bool { if case .troops = placing { return true }; return false }
    var placingSupport: Bool { if case .support = placing { return true }; return false }
    /// While support is armed, the support key (Q) brings the aircraft in from the west and the troops key (E) from the east;
    /// pressing the active side again goes back to the nearer edge.
    func chooseSupportSide(_ heading: Double) {
        world.supportSide = world.supportSide == heading ? nil : heading
        let sides = "\(k(.support)) WEST · \(k(.troops)) EAST"
        world.status = world.supportSide.map{ "SUPPORT RUNS IN FROM THE \($0 > 0 ? "WEST" : "EAST") · \(sides)" }
            ?? "SUPPORT RUNS IN FROM THE NEARER EDGE · \(sides)"
        sound.play(SoundEvent(cue:.select))
    }
    /// Opens the requisition menu on `tab`, switches to it, or closes the menu if it is already showing.
    func toggleDeployMenu(_ tab: RequisitionTab = .troops) {
        if (deployMenu && deployTab == tab) || (!deployMenu && placing != nil) { closeDeploy() }
        else {
            placing = nil; deployMenu = true; deployTab = tab; help = false
            if tab == .troops { showDeployZone() }
        }
        sound.play(SoundEvent(cue:.select))
    }
    /// Arms placement for the open tab's offer if it can be bought; otherwise explains why not.
    func choose(_ i:Int) {
        let support = deployMenu && deployTab == .support
        guard i < (support ? World.support.count : World.offers.count) else { return }
        if let reason = support ? world.refusal(World.support[i]) : world.refusal(World.offers[i]) {
            world.status = "REQUISITION DENIED · \(reason)"
            sound.play(SoundEvent(cue:.cease)); return
        }
        deployMenu = false
        if support {
            placing = .support(i)
            world.status = (World.support[i].kind == .gunRun ? "CLICK THE GROUND TO STRAFE"
                : World.support[i].kind == .firebomb ? "CLICK THE GROUND TO FIREBOMB"
                : World.support[i].kind == .drone ? "CLICK WHERE THE DRONE SHOULD FLY TO, THEN STEER IT"
                : "CLICK THE MAP TO DROP A \(World.support[i].name)")+" · \(k(.support))/\(k(.troops)) RUN IN FROM WEST/EAST · RIGHT-CLICK OR ESC WHEN DONE"
        } else {
            placing = .troops(i); showDeployZone()
            world.status = "PLACE \(World.offers[i].name) IN THE LANDING ZONE · RIGHT-CLICK OR ESC WHEN DONE"
        }
        sound.play(SoundEvent(cue:.select))
    }
    func place(_ p: Placement,at x:Double) {
        // Stay armed for the next placement while the offer is still affordable.
        switch p {
        case .troops(let i):
            guard world.purchase(World.offers[i],at:x) else { return }
            if world.refusal(World.offers[i]) != nil { placing = nil }
        case .support(let i):
            guard world.purchase(World.support[i],at:x) else { return }
            if world.refusal(World.support[i]) != nil { placing = nil }
        }
    }
    /// Pans to the landing zone if none of it is on screen.
    func showDeployZone() {
        let a = toScreen(Vec(x:World.deployZone.lowerBound,y:0)).x, b = toScreen(Vec(x:World.deployZone.upperBound,y:0)).x
        if b < 0 || a > 1440 { camera.x = (World.deployZone.lowerBound+World.deployZone.upperBound)/2; clampCamera() }
    }
    /// Green band over the landing zone, drawn in world space.
    func drawDeployZone(_ view: NSRect) {
        let z = World.deployZone, pulse = 0.5+0.5*sin(world.elapsed*3)
        let top = max(view.minY,World.top-360), h = World.bottom-top
        rect(z.lowerBound,top,z.upperBound-z.lowerBound,h,Tac.green,0.05+0.03*pulse)
        for x in [z.lowerBound,z.upperBound] { rect(x-1,top,2,h,Tac.green,0.55) }
        var x = z.lowerBound
        while x < z.upperBound { rect(x,world.ground(at:x)-2,8,2,Tac.green,0.8); x += 16 }
    }
    /// Translucent preview of the troops at the pointer, red outside the zone.
    func drawPlacementGhost(_ offer: TroopOffer) {
        let w = toWorld(pointer), ok = World.deployZone.contains(w.x) && world.refusal(offer) == nil
        for k in 0..<offer.count {
            var x = w.x+(Double(k)-Double(offer.count-1)/2)*12
            if ok { x = min(World.deployZone.upperBound,max(World.deployZone.lowerBound,x)) }
            drawSoldier(Soldier(id:0,position:Vec(x:x,y:world.ground(at:x)),kind:offer.kind,selected:false),ghost:true)
        }
        let g = world.ground(at:w.x)
        let c = ok ? Tac.green : Tac.red
        line([CGPoint(x:w.x-14,y:g),CGPoint(x:w.x+14,y:g)],c,2)
        if !ok { line([CGPoint(x:w.x-6,y:g-36),CGPoint(x:w.x+6,y:g-24)],c,2); line([CGPoint(x:w.x+6,y:g-36),CGPoint(x:w.x-6,y:g-24)],c,2) }
    }
    /// An ammo crate in world space: under its parachute while falling, then sitting inside
    /// a pulsing ring that marks how far it reaches.
    func drawCrate(_ crate: SupplyCrate, ghost: Bool = false) {
        let x = floor(crate.position.x), y = floor(crate.position.y), a = ghost ? 0.5 : 1.0
        if crate.landed || ghost {
            let fade = ghost ? 1 : min(1,crate.life/5)
            let pulse = 0.5+0.5*sin(world.elapsed*3)
            let r = World.crateRadius, cy = y-6
            circle(x,cy,r,Tac.green,(0.04+0.03*pulse)*fade)
            let ring = NSBezierPath(ovalIn:NSRect(x:x-r,y:cy-r,width:r*2,height:r*2))
            ring.lineWidth = 1.5/zoom; ring.setLineDash([6/zoom,5/zoom],count:2,phase:world.elapsed*8/zoom)
            color(Tac.green,(0.35+0.25*pulse)*fade).setStroke(); ring.stroke()
        } else {
            // Parachute canopy and rigging lines.
            let top = y-46
            polygon([CGPoint(x:x-20,y:top+8),CGPoint(x:x-14,y:top),CGPoint(x:x,y:top-4),CGPoint(x:x+14,y:top),CGPoint(x:x+20,y:top+8)],0xd8cba4,a)
            for k in stride(from:-1.0,through:1.0,by:1) { rect(x+k*10-1,top+2,3,6,0xa89d7c,a) }
            for k in [-20.0,0,20] { line([CGPoint(x:x+k,y:top+8),CGPoint(x:x+k*0.3,y:y-12)],0x8a8670,1,a*0.9) }
        }
        rect(x-8,y-12,16,12,0x6b5a3c,a)
        rect(x-8,y-12,16,2,0x8f7a52,a); rect(x-8,y-2,16,2,0x3f3424,a)
        rect(x-1,y-12,2,12,0x3f3424,a)
        rect(x-6,y-8,3,3,Tac.amber,a); rect(x+3,y-8,3,3,Tac.amber,a)
    }
    /// A C-130-style four-engine transport seen side-on, facing its heading: a deep, stubby
    /// fuselage with a rounded nose and stepped cockpit, a high wing on top with
    /// turboprop nacelles, landing-gear blisters on the belly, and an upswept tail with a
    /// rear cargo ramp that lowers as the plane nears the drop.
    func drawPlane(_ plane: SupplyPlane) {
        let ramp = plane.x-plane.heading*World.rampOffset
        drawTransport(x:plane.x,y:plane.y,heading:plane.heading,open:plane.dropped || (ramp-plane.dropX)*plane.heading > -World.releaseLead-320)
    }
    /// The C-130 at (`px`,`py`), ramp open or shut, nose toward `heading` (+1 east, -1 west).
    /// The firebomber carries an orange tail band.
    func drawTransport(x px: Double, y py: Double, heading: Double, open: Bool, firebomber: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let x = floor(px), y = floor(py)
        // Drawn facing east; a westbound plane is mirrored about its centre.
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.translateBy(x:x,y:0); ctx.scaleBy(x:heading < 0 ? -1 : 1,y:1); ctx.translateBy(x:-x,y:0)
        func shape(_ points: [(Double,Double)],_ c: UInt32,_ a: Double = 1) { polygon(points.map{CGPoint(x:x+$0.0,y:y+$0.1)},c,a) }
        let paint: UInt32 = 0x5d695f, top: UInt32 = 0x7b887c, belly: UInt32 = 0x46514a, dark: UInt32 = 0x2e3732, glass: UInt32 = 0x1c2a2e
        // Far-side engines and horizontal stabiliser, drawn first so the near side overlaps them.
        shape([(-62,-13),(-96,-14),(-98,-10),(-62,-9)],dark)
        shape([(4,-27),(38,-27),(46,-23),(46,-19),(4,-19)],dark)
        // Tall swept tail fin with its dorsal fillet.
        shape([(-44,-16),(-60,-22),(-74,-52),(-87,-54),(-91,-50),(-91,-14)],paint)
        shape([(-74,-52),(-87,-54),(-91,-50),(-89,-47),(-76,-49)],top)
        shape([(-80,-40),(-90,-40),(-90,-34),(-81,-34)],Tac.amber,0.5)
        if firebomber { shape([(-70,-30),(-82,-46),(-86,-46),(-73,-28)],GameView.flameOrange,0.8) }
        rect(x-89,y-24,1,10,dark,0.6)
        // Fuselage: rear upsweep to the tail cone, the deep main barrel, and a rounded nose.
        let hull: [(Double,Double)] = [(-90,-16),(-92,-11),(-88,-7),(-46,16),(64,16),(78,14),(88,9),(93,3),(94,-2),(91,-8),(84,-13),(74,-17),(-40,-17)]
        shape(hull,paint)
        shape([(-40,-17),(74,-17),(80,-15),(-60,-15),(-90,-16)],top)
        shape([(-46,16),(64,16),(78,14),(84,11),(-42,11),(-60,7)],belly)
        // Stepped cockpit glazing and the nose radome seam.
        shape([(70,-15),(80,-14),(86,-10),(89,-6),(78,-7),(70,-9)],glass)
        rect(x+77,y-14,1,7,paint); rect(x+83,y-11,1,5,paint)
        shape([(70,-9),(78,-7),(89,-6),(89,-5),(70,-8)],0x9fc8cc,0.35)
        rect(x+88,y-4,1,12,dark,0.5)
        // Crew door, troop door, and a row of round cabin windows.
        rect(x+56,y-8,7,16,dark,0.45); rect(x+57,y-6,5,3,glass)
        for wx in [-24.0,-6,26,42] { circle(x+wx,y-5,1.8,glass) }
        rect(x-38,y-6,7,15,dark,0.45)
        // Landing-gear blisters along the belly.
        shape([(-16,16),(-12,9),(32,9),(38,15),(34,20),(-12,20)],belly)
        rect(x-8,y+8,1,10,dark,0.5); rect(x+12,y+8,1,10,dark,0.5)
        // Panel lines.
        for px in [-40.0,0,40] { rect(x+px,y-16,1,30,dark,0.25) }
        rect(x-40,y+2,106,1,dark,0.2)
        // Rear cargo ramp: a seam when closed, swung down into the slipstream when open.
        if open {
            shape([(-44,13),(-86,-6),(-82,-2),(-44,15)],0x111614)
            shape([(-46,14),(-72,24),(-74,22),(-48,12)],belly)
            circle(x-50,y-10,2,Tac.amber,Int(world.elapsed*4)%2 == 0 ? 1 : 0.3)
        } else { line([CGPoint(x:x-46,y:y+13),CGPoint(x:x-86,y:y-6)],dark,1,0.7) }
        // High wing sitting on top of the fuselage, with its root fairing.
        shape([(-22,-17),(-10,-23),(40,-23),(50,-17)],paint)
        shape([(-6,-26),(44,-26),(48,-23),(-10,-22)],top)
        rect(x-6,y-22,52,1,dark,0.5)
        // Near-side turboprops: the inboard engine sits just behind and above the outboard
        // one, as they overlap side-on. Streamlined nacelles reach well ahead of the wing,
        // with a chin intake, a spinner, and a translucent four-blade prop disc.
        for (n,ex) in [(0,-2.0),(1,6.0)] {
            let lift = n == 0 ? -3.0 : 0, shade = n == 0 ? belly : paint
            shape([(ex,-24+lift),(ex+34,-24+lift),(ex+40,-21+lift),(ex+40,-14+lift),(ex+28,-11+lift),(ex+8,-12+lift),(ex-2,-17+lift)],shade)
            if n == 1 {
                rect(x+ex+4,y-24,30,2,top)
                rect(x+ex+28,y-13,9,3,dark)
                rect(x+ex+12,y-17,14,1,dark,0.5)
            }
            shape([(ex+40,-22+lift),(ex+44,-20+lift),(ex+46,-17.5+lift),(ex+44,-15+lift),(ex+40,-13+lift)],0x9aa398)
            let hub = Vec(x:x+ex+45,y:y-17.5+lift)
            let disc = NSBezierPath(ovalIn:NSRect(x:hub.x-2.5,y:hub.y-21,width:5,height:42))
            color(0xc8ccc0,n == 1 ? 0.14 : 0.08).setFill(); disc.fill()
            disc.lineWidth = 0.6; color(0xc8ccc0,n == 1 ? 0.28 : 0.14).setStroke(); disc.stroke()
            let spin = world.elapsed*38+ex
            for b in 0..<2 {
                let reach = 20*sin(spin+Double(b)*Double.pi/2)
                rect(hub.x-1.25,min(hub.y,hub.y+reach),2.5,abs(reach),0x2a302c,n == 1 ? 0.55 : 0.3)
            }
        }
    }
    /// An A-10-style ground-attack jet seen side-on, facing its heading and pitched along its dive:
    /// a long slim fuselage with the cannon muzzle under the nose, a bubble canopy well
    /// forward, a straight low wing hung with stores, two podded engines high on the rear
    /// fuselage, and a twin-fin tail.
    func drawJet(_ jet: StrafeJet) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let (y,pitch) = jet.path
        ctx.saveGState()
        ctx.translateBy(x:floor(jet.x),y:floor(y)); ctx.scaleBy(x:jet.heading < 0 ? -1 : 1,y:1); ctx.rotate(by:pitch)
        func shape(_ points: [(Double,Double)],_ c: UInt32,_ a: Double = 1) { polygon(points.map{CGPoint(x:$0.0,y:$0.1)},c,a) }
        let paint: UInt32 = 0x646c70, top: UInt32 = 0x7d868a, belly: UInt32 = 0x50585c, dark: UInt32 = 0x2a3033, glass: UInt32 = 0x1c2a2e
        // Far-side fin and engine, tucked behind the near ones.
        shape([(-52,-6),(-55,-24),(-49,-24),(-44,-6)],dark)
        shape([(-34,-17),(-14,-17),(-11,-14),(-14,-12),(-34,-12)],dark)
        // Horizontal tailplane running out to the fins.
        shape([(-58,-6),(-40,-6),(-38,-4),(-58,-3)],belly)
        // Fuselage: tapered tail cone, slim body, and a blunt nose over the gun.
        shape([(-58,-5),(-58,-1),(-44,3),(30,5),(44,5),(52,3),(54,0),(52,-3),(44,-6),(34,-8),(18,-8),(-30,-6)],paint)
        shape([(-58,-5),(-30,-6),(18,-8),(34,-8),(44,-6),(40,-5),(-30,-4)],top)
        shape([(-44,3),(30,5),(44,5),(50,3),(-30,2)],belly)
        // Bubble canopy with a frame bar and a highlight.
        shape([(24,-8),(27,-13),(33,-14),(38,-12),(41,-8)],glass)
        rect(31,-14,1,6,paint); shape([(27,-12),(32,-13),(30,-12)],0x9fc8cc,0.4)
        // Cannon muzzle just under the nose.
        rect(52,0.5,6,2.5,dark); rect(56,0.5,2,2.5,0x14181a)
        // Straight wing seen edge-on, with pylons and stores beneath.
        shape([(-10,1),(16,0),(20,2),(16,4),(-10,4)],belly)
        rect(-10,1,28,1,top,0.6)
        for (sx,len) in [(-6.0,12.0),(8.0,9.0)] {
            rect(sx+3,4,1.5,3,dark)
            shape([(sx,7),(sx+len,7),(sx+len+2,8.5),(sx+len,10),(sx,10)],0x4a5054)
        }
        // Near engine pod on its pylon, with the intake ring and exhaust.
        rect(-26,-9,6,3,belly)
        shape([(-38,-15),(-34,-19),(-12,-19),(-9,-16),(-12,-11),(-34,-11)],paint)
        shape([(-34,-19),(-12,-19),(-10,-17),(-34,-17)],top)
        rect(-12,-19,2,8,dark); rect(-39,-15,2,4,0x1a1e20)
        // Near fin at the end of the tailplane.
        shape([(-58,-6),(-61,-27),(-54,-27),(-48,-6)],paint)
        shape([(-61,-27),(-54,-27),(-55,-24),(-60.5,-24)],top)
        // Panel lines.
        for px in [-30.0,0,20] { rect(px,-6,0.8,10,dark,0.3) }
        if jet.flash > 0 {
            let m = World.gunMuzzle
            polygon([CGPoint(x:m.x+1,y:m.y-3),CGPoint(x:m.x+16,y:m.y),CGPoint(x:m.x+1,y:m.y+3)],0xffe8b2,0.9)
            circle(m.x+3,m.y,4,0xffb251,0.8)
        }
        ctx.restoreGState()
    }
    /// A kamikaze quadcopter seen side-on, leaning with its tilt: a squat body with the charge
    /// slung under it, an arm out to a motor at each end, and a rotor blur that thickens with
    /// throttle and stops once the battery is dead.
    func drawDrone(_ d: Drone, ghost: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if ghost { ctx.setAlpha(0.5) }
        ctx.translateBy(x:d.position.x,y:d.position.y); ctx.rotate(by:d.tilt)
        let body: UInt32 = 0x3a4246, dark: UInt32 = 0x1e2427
        rect(-11,-2,22,2,dark)
        rect(-5,-4,10,5,body); rect(-4,-4,8,1,0x56606a)
        // Charge and its fuse cap under the body.
        rect(-3,1,6,3,0x6b5a3a); rect(-1.5,4,3,1.5,0xd8a040)
        for sx in [-10.0,10.0] {
            rect(sx-1,-5,2,4,dark)
            if d.powered {
                let blur = NSBezierPath(ovalIn:NSRect(x:sx-7,y:-6.5,width:14,height:2.5))
                color(0xc8ccc0,0.2+0.35*d.throttle).setFill(); blur.fill()
                let spin = sin(world.elapsed*60+sx)*6
                rect(sx+min(0,spin),-5.8,abs(spin),1,0x2a302c,0.7)
            } else { rect(sx-6,-5.5,12,1,0x2a302c) }
        }
        if Int(world.elapsed*4) % 2 == 0 && !ghost && !d.shorted { rect(-1,-5,2,1.5,0xff4030) }
        ctx.restoreGState()
    }
    /// A piloted drone's blast ring and a faint line to the point it is flying to.
    func drawDroneAim(_ d: Drone) {
        guard d.piloted else { return }
        let r = World.droneBlastRadius, ring = NSBezierPath(ovalIn:NSRect(x:d.position.x-r,y:d.position.y-r,width:r*2,height:r*2))
        ring.lineWidth = 1/zoom; color(Tac.red,0.3).setStroke(); ring.stroke()
        guard d.powered else { return }
        line([CGPoint(x:d.position.x,y:d.position.y),CGPoint(x:d.aim.x,y:d.aim.y)],Tac.amber,1/zoom,0.25)
        let a = d.aim, s = 4/zoom
        polygon([CGPoint(x:a.x,y:a.y-s),CGPoint(x:a.x+s,y:a.y),CGPoint(x:a.x,y:a.y+s),CGPoint(x:a.x-s,y:a.y)],Tac.amber,0.5)
    }
    /// Preview of a support call at the pointer: where it will land and what it covers.
    func drawSupportGhost(_ offer: SupportOffer) {
        let w = toWorld(pointer)
        guard w.x >= 0 && w.x <= World.width else { return }
        // Run-in lines point the way the aircraft will come: the chosen side, else the nearer edge.
        let h = world.approach(toward:w.x)
        switch offer.kind {
        case .supplyCrate:
            let g = world.ground(at:w.x), alt = world.transportAltitude
            line([CGPoint(x:w.x,y:alt),CGPoint(x:w.x,y:g-14)],Tac.amber,1/zoom,0.35)
            line([CGPoint(x:w.x-260*h,y:alt),CGPoint(x:w.x+60*h,y:alt)],Tac.amber,1/zoom,0.25)
            polygon([CGPoint(x:w.x+60*h,y:alt),CGPoint(x:w.x+52*h,y:alt-4),CGPoint(x:w.x+52*h,y:alt+4)],Tac.amber,0.35)
            drawCrate(SupplyCrate(position:Vec(x:w.x,y:g),landed:true),ghost:true)
            if world.refusal(offer) != nil { line([CGPoint(x:w.x-6,y:g-36),CGPoint(x:w.x+6,y:g-24)],Tac.red,2); line([CGPoint(x:w.x+6,y:g-36),CGPoint(x:w.x-6,y:g-24)],Tac.red,2) }
        case .gunRun:
            // The strip the burst walks across, and the jet's line of fire onto it.
            let half = World.strafeLength/2, g = world.ground(at:w.x)
            var x = w.x-half, ticks: [CGPoint] = []
            while x <= w.x+half { ticks.append(CGPoint(x:x,y:world.ground(at:x))); x += 8 }
            line(ticks,Tac.red,2.5/zoom,0.7)
            for p in ticks.enumerated() where p.offset%3 == 0 { line([CGPoint(x:p.element.x,y:p.element.y),CGPoint(x:p.element.x+5,y:p.element.y-8)],Tac.red,1/zoom,0.5) }
            let low = world.strafeFloor(w.x), window = World.fireWindow, cruise = world.jetCruise
            let a = CGPoint(x:w.x+h*(window.lowerBound+World.gunMuzzle.x),y:World.strafePath(window.lowerBound,low:low,cruise:cruise).y)
            let b = CGPoint(x:w.x+h*(window.upperBound+World.gunMuzzle.x),y:World.strafePath(window.upperBound,low:low,cruise:cruise).y)
            line([a,CGPoint(x:w.x-h*half,y:world.ground(at:w.x-h*half))],Tac.red,1/zoom,0.3)
            line([b,CGPoint(x:w.x+h*half,y:world.ground(at:w.x+h*half))],Tac.red,1/zoom,0.3)
            line([CGPoint(x:a.x-200*h,y:cruise),a,b],Tac.red,1/zoom,0.35)
            polygon([CGPoint(x:b.x+8*h,y:b.y),CGPoint(x:b.x,y:b.y-4),CGPoint(x:b.x,y:b.y+4)],Tac.red,0.4)
            line([CGPoint(x:w.x-6,y:g-14),CGPoint(x:w.x+6,y:g-14)],Tac.red,1.5/zoom); line([CGPoint(x:w.x,y:g-20),CGPoint(x:w.x,y:g-8)],Tac.red,1.5/zoom)
            if world.refusal(offer) != nil { line([CGPoint(x:w.x-6,y:g-36),CGPoint(x:w.x+6,y:g-24)],Tac.red,2); line([CGPoint(x:w.x+6,y:g-36),CGPoint(x:w.x-6,y:g-24)],Tac.red,2) }
        case .firebomb:
            drawFirebombGhost(offer,at:w.x)
        case .drone:
            // The run in at cruise height and where control passes to the player.
            let alt = world.droneCruise, g = world.ground(at:w.x)
            line([CGPoint(x:w.x-260*h,y:alt),CGPoint(x:w.x-14*h,y:alt)],Tac.amber,1/zoom,0.3)
            polygon([CGPoint(x:w.x-14*h,y:alt),CGPoint(x:w.x-22*h,y:alt-4),CGPoint(x:w.x-22*h,y:alt+4)],Tac.amber,0.35)
            line([CGPoint(x:w.x,y:alt+10),CGPoint(x:w.x,y:g-4)],Tac.amber,1/zoom,0.2)
            drawDrone(Drone(position:Vec(x:w.x,y:alt),velocity:Vec(x:0,y:0),heading:h,arrival:Vec(x:w.x,y:alt),aim:Vec(x:w.x,y:alt)),ghost:true)
            if world.refusal(offer) != nil { line([CGPoint(x:w.x-6,y:alt-18),CGPoint(x:w.x+6,y:alt-6)],Tac.red,2); line([CGPoint(x:w.x+6,y:alt-18),CGPoint(x:w.x-6,y:alt-6)],Tac.red,2) }
        }
    }
    /// Screen-space labels over each crate: inbound while falling, rounds and seconds left once down.
    func drawCrateTags() {
        for crate in world.crates {
            let p = toScreen(Vec(x:crate.position.x,y:crate.position.y-(crate.landed ? 16 : 52)))
            guard p.x > -60 && p.x < 1500 && p.y > 110 && p.y < 775 else { continue }
            let label = crate.landed ? "AMMO \(crate.stock) RDS · \(Int(crate.life.rounded(.up)))S" : "AMMO DROP"
            text(label,p.x-Double(label.count)*2.7,p.y-14,9,Tac.amber,.bold,true)
        }
        for plane in world.planes {
            let p = toScreen(Vec(x:plane.x,y:plane.y-60))
            guard p.x > -60 && p.x < 1500 && p.y > 110 && p.y < 775 else { continue }
            text(plane.dropped ? "SUPPLY PLANE · RTB" : "SUPPLY PLANE",p.x-36,p.y-14,9,Tac.amber,.bold,true)
        }
        if let d = world.drone {
            let p = toScreen(Vec(x:d.position.x,y:d.position.y-12))
            if p.x > -60 && p.x < 1500 && p.y > 110 && p.y < 775 {
                let label = !d.piloted ? "DRONE · INBOUND" : d.powered ? "DRONE · \(Int(d.battery.rounded(.up)))S" : "DRONE · NO POWER"
                let c = d.piloted && (!d.powered || d.battery < 5) ? Tac.red : Tac.amber
                text(label,p.x-textWidth(label,9,.bold,true)/2,p.y-26,9,c,.bold,true)
                if d.piloted {
                    let share = max(0,d.battery)/World.droneBattery, w = 24.0
                    rect(p.x-w/2-1,p.y-12,w+2,5,0x000000,0.55); rect(p.x-w/2,p.y-11,w*share,3,c)
                }
            }
        }
        for jet in world.jets {
            let p = toScreen(Vec(x:jet.x,y:jet.path.y-34))
            guard p.x > -60 && p.x < 1500 && p.y > 110 && p.y < 775 else { continue }
            text(jet.fired >= World.gunRounds ? "GUN RUN · RTB" : "GUN RUN",p.x-24,p.y-14,9,Tac.red,.bold,true)
        }
    }
    /// Screen-space ammo gauge over every soldier, so it stays legible at any zoom. The bar
    /// turns amber and gains a LOW tag at a quarter load; an empty soldier gets a blinking
    /// red NO AMMO tag instead. A green REARMED tag follows a crate refill.
    func drawAmmoTags() {
        let blink = Int(world.elapsed*3) % 2 == 0
        for s in world.soldiers {
            let p = toScreen(Vec(x:s.position.x,y:s.position.y-Soldier.height))
            guard p.x > -30 && p.x < 1470 && p.y > 104 && p.y < 808 else { continue }
            let w = 18.0, x = floor(p.x-w/2), y = floor(p.y-(s.selected ? 18 : 9)*max(0.6,min(1,zoom)))
            let share = Double(max(0,s.ammo))/Double(s.kind.magazine)
            let c = s.outOfAmmo ? Tac.red : s.lowAmmo ? Tac.amber : Tac.green
            rect(x-1,y-1,w+2,5,0x000000,0.55)
            rect(x,y,w*share,3,c,s.lowAmmo || s.outOfAmmo || s.selected ? 1 : 0.6)
            if s.rearmed > 0 {
                text("REARMED",x-12,y-14,9,Tac.green,.heavy,true)
            } else if s.outOfAmmo {
                line([CGPoint(x:x-1,y:y-1),CGPoint(x:x+w+1,y:y-1),CGPoint(x:x+w+1,y:y+4),CGPoint(x:x-1,y:y+4),CGPoint(x:x-1,y:y-1)],Tac.red,1,blink ? 1 : 0.4)
                text("NO AMMO",x-12,y-14,9,Tac.red,.heavy,true)
            } else if s.lowAmmo {
                text("LOW",x+w+3,y-5,9,Tac.amber,.heavy,true)
            }
        }
    }
    func drawDeployMenu() {
        let f = deployFrame
        panel(f,Tac.panel,0.95,Tac.amber,12); brackets(f.insetBy(dx:-6,dy:-6),Tac.amber,12,0.8)
        rect(f.minX,f.minY,f.width-12,22,Tac.amber,0.85)
        text("▲ REQUISITION // \(deployTab == .troops ? "DEPLOY TROOPS" : "CALL IN SUPPORT")",f.minX+12,f.minY+5,10,0x1a1408,.heavy,true)
        text("[ESC] CLOSE",f.maxX-94,f.minY+5,10,0x1a1408,.heavy,true)
        for (tab,label) in [(RequisitionTab.troops,"TROOPS  [\(k(.troops))]"),(.support,"SUPPORT  [\(k(.support))]")] {
            let r = deployTabRect(tab), open = deployTab == tab
            let hovered = isHovering && r.contains(NSPoint(x:pointer.x,y:pointer.y))
            rect(r.minX,r.minY,r.width,r.height,open ? Tac.hover : Tac.raised)
            rect(r.minX,r.maxY-2,r.width,2,open ? Tac.amber : (hovered ? Tac.dim : Tac.rule))
            text(label,r.minX+12,r.minY+6,10,open ? Tac.amber : (hovered ? Tac.text : Tac.dim),.heavy,true)
        }
        text("CREDITS AVAILABLE",f.minX+16,f.minY+60,9,Tac.dim,.bold,true)
        text(creditsText,f.minX+16,f.minY+72,20,Tac.amber,.semibold,true)
        text("THIS ROUND'S GRANT",f.minX+230,f.minY+60,9,Tac.dim,.bold,true)
        let grant = ([World.startingCredits,world.carriedCredits,world.broughtCredits].filter{$0 > 0}).map(cr).joined(separator:" + ")
        text(grant,f.minX+230,f.minY+76,13,Tac.text,.semibold,true)
        let rows: [(name:String,detail:String,cost:Int,reason:String?)] = deployTab == .troops
            ? World.offers.map{($0.name,$0.detail,$0.cost,world.refusal($0))}
            : World.support.map{($0.name,$0.detail,$0.cost,world.refusal($0))}
        for (i,offer) in rows.enumerated() {
            let r = deployRow(i), reason = offer.reason
            let hovered = isHovering && r.contains(NSPoint(x:pointer.x,y:pointer.y))
            let accent = reason == nil ? (hovered ? Tac.green : Tac.amber) : Tac.red
            panel(r,hovered && reason == nil ? Tac.hover : Tac.raised,1,hovered ? accent : Tac.rule,8)
            rect(r.minX,r.minY,3,r.height,accent)
            if hovered { brackets(r.insetBy(dx:-4,dy:-4),accent,7) }
            text("[\(i+1)]",r.minX+12,r.minY+20,11,reason == nil ? Tac.text : Tac.dim,.bold,true)
            text(offer.name,r.minX+50,r.minY+10,15,reason == nil ? Tac.bright : Tac.dim,.heavy,true)
            text(offer.detail,r.minX+50,r.minY+36,9,Tac.dim,.medium,true)
            text(cr(offer.cost),r.maxX-104,r.minY+10,14,reason == nil ? Tac.amber : Tac.dim,.bold,true)
            text(reason ?? (deployTab == .troops ? "READY ▸ PLACE" : "READY ▸ DROP"),r.maxX-104,r.minY+36,9,reason == nil ? Tac.green : Tac.red,.bold,true)
        }
        if deployTab == .support {
            text("Crates rearm troops in their ring; the jet strafes the strip you",f.minX+16,f.minY+350,10,Tac.dim)
            text("click; the C-130 sets it burning; the drone is yours to fly in.",f.minX+16,f.minY+366,10,Tac.dim)
        }
        text(deployTab == .troops ? "[1-\(World.offers.count)] SELECT · THEN CLICK INSIDE THE GREEN LANDING ZONE" : "[1-\(World.support.count)] SELECT · THEN CLICK THE MAP TO CALL IT IN",f.minX+16,f.maxY-20,9,Tac.dim,.medium,true)
    }
    func extract() {
        let cleared = world.cleared
        guard world.extract() else { sound.play(SoundEvent(cue:.cease)); return }
        unlockedNow = world.cleared > cleared && world.cleared < levels.count ? world.cleared : nil
        debrief = true; panKeys.removeAll(); closeDeploy()
        sound.sync(paused:true,active:NSApp.isActive)
        sound.play(SoundEvent(cue:.select))
    }
    func debriefButton(_ i:Int) -> NSRect { NSRect(x:560+Double(i)*166,y:580,width:154,height:58) }
    func drawDebrief() {
        rect(0,0,1440,900,0x070a07,0.82)
        let r = NSRect(x:520,y:250,width:400,height:410)
        brackets(r,Tac.green,16,0.6,2)
        rect(540,272,5,40,Tac.green)
        text("MISSION COMPLETE",558,272,28,Tac.bright,.heavy,true)
        let unlocked = unlockedNow.map { String(format:" · OP-%02d UNLOCKED",$0+1) } ?? ""
        text("\(World.spec.operation) · PLATOON EXTRACTED"+unlocked,560,312,10,Tac.green,.medium,true)
        let t = Int(world.elapsed)
        let lines = [("FINAL POINTS",pts(world.points)),("GOAL",pts(World.requirement)),
                     ("NEXT ROUND CREDITS","+\(cr(World.credits(for:world.points)))"),("CREDITS BANKED","+\(cr(world.banked))"),
                     ("HVTs DESTROYED","\(world.objectives.filter{$0.destroyed}.count) / \(world.objectives.count)"),
                     ("MISSION TIME",String(format:"%02d:%02d",t/60,t%60)),("BLOCKS DESTROYED","\(world.destroyed+world.collapsed)")]
        for (i,l) in lines.enumerated() {
            let ly = 346+Double(i)*31
            text(l.0,560,ly,11,Tac.dim,.bold,true)
            text(l.1,760,ly-3,16,i == 2 || i == 3 ? Tac.amber : i == 0 ? Tac.green : Tac.bright,.semibold,true)
            rect(560,ly+24,340,1,Tac.rule,0.6)
        }
        for (i,option) in debriefOptions.enumerated() {
            let b = debriefButton(i)
            let hovered = isHovering && b.contains(NSPoint(x:pointer.x,y:pointer.y))
            panel(b,hovered ? Tac.hover : Tac.raised,1,hovered ? Tac.green : Tac.rule)
            rect(b.minX,b.minY,3,b.height,hovered ? Tac.green : Tac.amber)
            text(option.0,b.minX+14,b.minY+10,13,Tac.bright,.bold,true)
            text(option.1,b.minX+14,b.minY+34,7,Tac.dim,.medium,true)
        }
    }
    func chooseDebriefOption(_ i:Int) {
        debrief = false
        if i == 0 {
            sound.stopEffects(); world.reset(); closeDeploy()
            inMenu = true; help = true; resetCamera()
        } else {
            world.paused = false; previous = ProcessInfo.processInfo.systemUptime
            world.status = "OPERATION CONTINUES · PRESS \(k(.extract)) TO EXTRACT AGAIN"
        }
        sound.play(SoundEvent(cue:.select))
        needsDisplay = true
    }
    func point(_ event:NSEvent) -> Vec {
        let p = convert(event.locationInWindow,from:nil)
        return Vec(x:(p.x-offset.x)/scaleFactor,y:(p.y-offset.y)/scaleFactor)
    }
    override func mouseMoved(with event:NSEvent) { pointer = point(event); isHovering = true }
    override func mouseExited(with event:NSEvent) { isHovering = false }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event); pointer = p
        if escMenu {
            escMouseDown(NSPoint(x:p.x,y:p.y))
            return
        }
        if debrief {
            if let i = debriefOptions.indices.first(where:{ debriefButton($0).contains(NSPoint(x:p.x,y:p.y)) }) { chooseDebriefOption(i) }
            return
        }
        if inMenu {
            if lobbySettings { lobbySettingsMouseDown(NSPoint(x:p.x,y:p.y)); return }
            if settingsButton.contains(NSPoint(x:p.x,y:p.y)) { openLobbySettings(); return }
            if cheatButton.contains(NSPoint(x:p.x,y:p.y)) { toggleCheatBox(); return }
            if cheatOpen && !cheatField.contains(NSPoint(x:p.x,y:p.y)) { cheatOpen = false; cheatEntry = "" }
            if let i = levels.indices.first(where:{ levelCard($0).contains(NSPoint(x:p.x,y:p.y)) }) { startLevel(i) }
            else if let c = BankControl.allCases.first(where:{ bankButton($0).contains(NSPoint(x:p.x,y:p.y)) }), world.bank > 0 { adjustWithdrawal(c) }
            return
        }
        if p.y < 104 {
            let at = NSPoint(x:p.x,y:p.y)
            if menuButtonFrame.contains(at) { closeDeploy(); panKeys.removeAll(); openEscMenu() }
            else if guideButtonFrame.contains(at) { toggleHelp() }
            else if tempoCell(0).contains(at) { togglePause() }
            else if let i = World.speeds.indices.first(where:{ tempoCell($0+1).contains(at) }) { setSpeed(World.speeds[i]) }
            else if muteTagFrame.contains(at) && (sound.muted || !sound.available) { sound.toggleMute() }
            return
        }
        if deployMenu && !(p.y >= 827 && p.y <= 885) {
            if deployFrame.contains(NSPoint(x:p.x,y:p.y)) {
                if let tab = [RequisitionTab.troops,.support].first(where:{ deployTabRect($0).contains(NSPoint(x:p.x,y:p.y)) }) {
                    if tab != deployTab { deployTab = tab; sound.play(SoundEvent(cue:.select)) }
                    if tab == .troops { showDeployZone() }
                } else if let i = (0..<(deployTab == .troops ? World.offers.count : World.support.count)).first(where:{ deployRow($0).contains(NSPoint(x:p.x,y:p.y)) }) { choose(i) }
            } else { deployMenu = false }
            return
        }
        if p.y >= 808 {
            switch DockAction.allCases.first(where:{ dockFrame($0).contains(NSPoint(x:p.x,y:p.y)) }) {
            case .deploy?: toggleDeployMenu()
            case .selectAll?: selectAll()
            case .cease?: world.cease()
            case .extract?: extract()
            case nil: break
            }
        } else if p.y > 104 {
            if help && guideFrame.contains(NSPoint(x:p.x,y:p.y)) { toggleHelp(); return }
            if targetsHeader.contains(NSPoint(x:p.x,y:p.y)) { toggleTargets(); return }
            if minimapFrame.insetBy(dx:-6,dy:-6).contains(NSPoint(x:p.x,y:p.y)) { jumpToMinimap(p); return }
            if let placement = placing { place(placement,at:toWorld(p).x); return }
            // While a drone is under control, a click on the field sets it off.
            if world.drone?.piloted == true { world.detonateDrone(); needsDisplay = true; return }
            let w = toWorld(p), reach = 16/min(1,zoom), mid = Soldier.height/2
            if let index = world.soldiers.indices.min(by:{ hypot(world.soldiers[$0].position.x-w.x,world.soldiers[$0].position.y-mid-w.y) < hypot(world.soldiers[$1].position.x-w.x,world.soldiers[$1].position.y-mid-w.y) }), hypot(world.soldiers[index].position.x-w.x,world.soldiers[index].position.y-mid-w.y) < reach {
                // Clicking the only selected soldier again deselects them.
                let alone = world.soldiers[index].selected && world.soldiers.filter{$0.selected}.count == 1
                if alone && !event.modifierFlags.contains(.shift) { deselectAll(); needsDisplay = true; return }
                if event.modifierFlags.contains(.shift) { world.soldiers[index].selected.toggle() }
                else { for i in world.soldiers.indices { world.soldiers[i].selected = i == index } }
                sound.play(SoundEvent(cue:.select))
                if !world.soldiers.contains(where:{$0.selected}) { world.status = "SELECTION CLEARED · CLICK A SOLDIER OR PRESS \(k(.selectAll))" }
                else { world.status = world.rocketsSelected ? "RPG READY · AIM WITH THE POINTER, CLICK TO FIRE / RIGHT-CLICK TO MOVE" : "UNIT SELECTED · CLICK TO ATTACK / RIGHT-CLICK TO MOVE" }
            } else { press = (p,w,false) }
        }
        needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) {
        guard let pressed = press else { return }
        press = nil
        guard !inMenu && !escMenu && !debrief else { return }
        if pressed.boxing { boxSelect(from:pressed.world,to:toWorld(point(event)),adding:event.modifierFlags.contains(.shift)) }
        else { world.attack(pressed.world) }
        needsDisplay = true
    }
    /// The world rectangle a selection box spans, from its anchor to the pointer.
    func selectionBox(from a:Vec,to b:Vec) -> NSRect {
        NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
    }
    /// Soldiers whose body overlaps the box.
    func soldiersIn(_ box:NSRect) -> [Int] {
        world.soldiers.indices.filter{
            let s = world.soldiers[$0].position
            return box.intersects(NSRect(x:s.x-4,y:s.y-Soldier.height,width:8,height:Soldier.height))
        }
    }
    /// Selects the troops inside a dragged box; with Shift held they join the current selection.
    func boxSelect(from a:Vec,to b:Vec,adding:Bool) {
        let inside = Set(soldiersIn(selectionBox(from:a,to:b)))
        for i in world.soldiers.indices { world.soldiers[i].selected = inside.contains(i) || (adding && world.soldiers[i].selected) }
        sound.play(SoundEvent(cue:.select))
        let count = world.soldiers.filter{$0.selected}.count
        if count == 0 { world.status = "SELECTION CLEARED · CLICK A SOLDIER OR PRESS \(k(.selectAll))" }
        else { world.status = world.rocketsSelected ? "RPG READY · AIM WITH THE POINTER, CLICK TO FIRE / RIGHT-CLICK TO MOVE" : "\(count) SELECTED · CLICK TO ATTACK / RIGHT-CLICK TO MOVE" }
    }
    /// The dragged selection box and brackets on the troops it would take.
    func drawSelectionBox() {
        guard let pressed = press, pressed.boxing else { return }
        let a = toScreen(pressed.world), b = pointer
        let clampY = { (y:Double) in max(104,min(808,y)) }
        let r = NSRect(x:min(a.x,b.x),y:clampY(min(a.y,b.y)),width:abs(a.x-b.x),height:clampY(max(a.y,b.y))-clampY(min(a.y,b.y)))
        rect(r.minX,r.minY,r.width,r.height,Tac.green,0.08)
        line([CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.minX,y:r.minY)],Tac.green,1,0.7)
        for i in soldiersIn(selectionBox(from:pressed.world,to:toWorld(pointer))) {
            let s = toScreen(world.soldiers[i].position), h = Soldier.height*zoom
            brackets(NSRect(x:s.x-max(6,5*zoom),y:s.y-h-3,width:max(12,10*zoom),height:h+6),Tac.green,4,0.9,1)
        }
    }
    override func rightMouseDown(with event:NSEvent) {
        let p = point(event)
        if placing != nil || deployMenu { closeDeploy(); world.status = "DEPLOYMENT COMPLETE · AWAITING ORDERS"; return }
        if !inMenu && !escMenu && !debrief && p.y > 104 && p.y < 808 { world.move(toWorld(p).x) }
    }
    func jumpToMinimap(_ p: Vec) {
        let m = minimapFrame
        camera = Vec(x:(p.x-m.minX)/m.width*World.width,y:World.top+(p.y-m.minY)/m.height*(World.bottom-World.top))
        clampCamera()
    }
    override func mouseDragged(with event:NSEvent) {
        let p = point(event); pointer = p
        if let pressed = press, !pressed.boxing, hypot(p.x-pressed.screen.x,p.y-pressed.screen.y) >= boxThreshold { press?.boxing = true }
        if press != nil { needsDisplay = true; return }
        if !inMenu && !escMenu && minimapFrame.contains(NSPoint(x:p.x,y:p.y)) { jumpToMinimap(p) }
    }
    override func otherMouseDown(with event:NSEvent) { dragAnchor = point(event) }
    override func otherMouseDragged(with event:NSEvent) {
        guard let anchor = dragAnchor, !inMenu else { return }
        let p = point(event)
        camera = Vec(x:camera.x-(p.x-anchor.x)/zoom,y:camera.y-(p.y-anchor.y)/zoom)
        dragAnchor = p; pointer = p; clampCamera()
    }
    override func otherMouseUp(with event:NSEvent) { dragAnchor = nil }
    override func scrollWheel(with event:NSEvent) {
        guard !inMenu && !escMenu else { return }
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Two-finger trackpad scrolling pans; pinch (magnify) zooms.
            camera = Vec(x:camera.x-event.scrollingDeltaX/scaleFactor/zoom,y:camera.y-event.scrollingDeltaY/scaleFactor/zoom)
            clampCamera()
        } else {
            let step = Double(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY*0.01 : event.scrollingDeltaY*0.1)
            zoom(by:pow(2.0,step),at:point(event))
        }
    }
    override func magnify(with event:NSEvent) {
        guard !inMenu && !escMenu else { return }
        zoom(by:1+event.magnification,at:point(event))
    }
    override func keyUp(with event:NSEvent) { panKeys.remove(event.keyCode) }
    func togglePause() {
        world.paused.toggle()
        sound.sync(paused:world.paused,active:NSApp.isActive)
        sound.play(SoundEvent(cue:.pause))
    }
    func toggleHelp() { help.toggle(); sound.play(SoundEvent(cue:.select)) }
    func toggleTargets() { showTargets.toggle(); sound.play(SoundEvent(cue:.select)) }
    func resetMap() { sound.stopEffects(); world.reset(); closeDeploy() }
    /// True when there are troops and every one of them is selected; the dock button and
    /// the A key then deselect instead.
    var allSelected: Bool { !world.soldiers.isEmpty && world.soldiers.allSatisfy{$0.selected} }
    /// A and the dock button toggle: select the whole platoon, or clear it if it's all selected.
    func selectAll() {
        if allSelected { deselectAll(); return }
        sound.play(SoundEvent(cue:.select))
        for i in world.soldiers.indices { world.soldiers[i].selected = true }
        world.status = "PLATOON SELECTED · AWAITING ORDERS"
    }
    func deselectAll() {
        sound.play(SoundEvent(cue:.select))
        for i in world.soldiers.indices { world.soldiers[i].selected = false }
        world.status = "SELECTION CLEARED · CLICK A SOLDIER OR PRESS \(k(.selectAll))"
    }
    /// Key codes for Tab, which steps through settings tabs, and F1, which always opens the field guide.
    static let tabKey: UInt16 = 48, f1Key: UInt16 = 122
    /// Runs a rebindable in-game action. While support is armed, the support and troops keys
    /// pick the west and east run-in sides instead.
    func perform(_ action: KeyAction) {
        switch action {
        case .selectAll: selectAll()
        case .troops: if placingSupport { chooseSupportSide(-1) } else { toggleDeployMenu() }
        case .support: if placingSupport { chooseSupportSide(1) } else { toggleDeployMenu(.support) }
        case .extract: extract()
        case .cease: world.cease()
        case .pause: togglePause()
        case .speed: cycleSpeed()
        case .centre: focusSelection()
        case .targets: toggleTargets()
        case .guide: toggleHelp()
        case .detonate: if !world.detonateDrone() { world.status = "NO DRONE IN THE AIR · CALL ONE FROM SUPPORT [\(k(.support))]" }
        case .panLeft, .panRight, .panUp, .panDown: break
        case .zoomIn: zoom(by:1.25,at:Vec(x:720,y:456))
        case .zoomOut: zoom(by:0.8,at:Vec(x:720,y:456))
        case .zoomReset: zoom(by:1/zoom,at:Vec(x:720,y:456))
        case .mute: sound.toggleMute()
        case .volumeDown: sound.adjustVolume(-0.1)
        case .volumeUp: sound.adjustVolume(0.1)
        }
    }
    override func keyDown(with event:NSEvent) {
        guard !event.isARepeat else { return }
        let key = event.charactersIgnoringModifiers?.lowercased()
        let command = !event.modifierFlags.intersection([.command,.control]).isEmpty
        let action = command ? nil : binds.action(for:event.keyCode)
        if !inMenu && !escMenu && !debrief, let action, [.panLeft,.panRight,.panUp,.panDown].contains(action) { panKeys.insert(event.keyCode); return }
        if debrief {
            switch key {
            case "\r", "\u{3}": chooseDebriefOption(0)
            case "\u{1b}": chooseDebriefOption(1)
            case "f": window?.toggleFullScreen(nil)
            default: break
            }
            return
        }
        if escMenu {
            escKeyDown(key,event,command)
            return
        }
        if inMenu && lobbySettings && !command { lobbySettingsKeyDown(key,event); return }
        if inMenu && cheatOpen && !command { cheatKeyDown(event); return }
        if inMenu {
            switch key {
            case "f": window?.toggleFullScreen(nil)
            case "s": openLobbySettings()
            case _ where event.keyCode == 123 || event.keyCode == 0: adjustWithdrawal(.less)
            case _ where event.keyCode == 124 || event.keyCode == 2: adjustWithdrawal(.more)
            case "\r", "\u{3}": startLevel(nextLevel)
            case let key?: if let n = Int(key) { startLevel(n-1) } else { super.keyDown(with:event) }
            default: super.keyDown(with:event)
            }
            return
        }
        if let key, let n = Int(key), n >= 1 { choose(n-1); return }
        if let action { perform(action); return }
        switch key {
        case "f": window?.toggleFullScreen(nil)
        case "\u{1b}":
            if deployMenu || placing != nil { closeDeploy(); world.status = "DEPLOYMENT COMPLETE · AWAITING ORDERS" }
            else if world.soldiers.contains(where:{$0.selected}) { deselectAll() }
            else { panKeys.removeAll(); openEscMenu() }
        default: super.keyDown(with:event)
        }
    }
}
