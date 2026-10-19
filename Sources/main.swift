import AppKit

if CommandLine.arguments.contains("--self-test") {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n",stderr); exit(1) }
        print("PASS: \(message)")
    }
    let w = World()
    check(w.material(108*World.scale,34*World.scale) == 3,"bunker built from solid voxels")
    check(w.material(112*World.scale,38*World.scale) == 0,"bunker has open interior")
    w.spawn(4)
    check(w.soldiers.count == 4,"squad deploys four soldiers")
    let concreteBefore = w.voxels.filter{$0 == 3}.count
    w.attack(Vec(x:878,y:448))
    for _ in 0..<600 { w.update(1/60) }
    check(w.rounds > 12,"soldiers fire repeatedly at commanded target")
    check(w.destroyed > 0,"projectile impacts destroy terrain")
    check(w.voxels.filter{$0 == 3}.count < concreteBefore,"bunker takes material damage")
    let before = w.elapsed
    w.paused = true; w.update(1)
    check(w.elapsed == before,"pause freezes simulation")
    w.paused = false
    let real = w.elapsed
    w.speed = 4; w.advance(1/60)
    check(abs(w.elapsed-real-4.0/60) < 1e-9,"4x speed runs four simulation steps per frame")
    w.cycleSpeed()
    check(w.speed == 0.25,"speed cycles 4x back to 0.25x")
    let slow = w.elapsed
    w.advance(1/60)
    check(abs(w.elapsed-slow-0.25/60) < 1e-9,"0.25x speed runs a quarter-length step per frame")
    w.cycleSpeed()
    check(w.speed == 1,"speed cycles 0.25x up to 1x")
    w.cease()
    check(w.soldiers.allSatisfy{$0.target == nil},"cease fire clears all orders")
    let x = w.soldiers[0].position.x
    w.move(400)
    for _ in 0..<60 { w.update(1/60) }
    check(w.soldiers[0].position.x > x,"move command advances soldiers")
    for _ in 0..<12 { w.spawn(4) }
    check(w.soldiers.count == 52,"no unit cap")
    w.explode(at:Vec(x:0,y:World.top)); w.explode(at:Vec(x:World.width,y:World.bottom))
    check(true,"edge explosions remain in bounds")
    w.speed = 2; w.reset()
    check(w.soldiers.isEmpty && w.destroyed == 0 && w.shots.isEmpty,"reset restores clean map")
    check(w.speed == 1,"reset returns to real-time speed")
    print("All simulation checks passed.")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width:1280,height:800)
        window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Raining Hell"
        window.minSize = NSSize(width:960,height:622)
        window.backgroundColor = color(0x0c191f)
        window.appearance = NSAppearance(named:.darkAqua)
        window.collectionBehavior = [.fullScreenPrimary]
        let view = GameView(frame:NSRect(origin:.zero,size:size))
        if !CommandLine.arguments.dropFirst().contains(where:{ $0.hasPrefix("--") }) { view.persistBank() }
        window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        // Headless screenshots must not pull focus from whatever the user is doing.
        if !CommandLine.arguments.contains("--screenshot") { NSApp.activate(ignoringOtherApps:true) }
        // Full screen is saved like the other settings and restored on the next launch.
        if view.persistent {
            for (name,on) in [(NSWindow.didEnterFullScreenNotification,true),(NSWindow.didExitFullScreenNotification,false)] {
                NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { _ in UserDefaults.standard.set(on,forKey:"fullScreen") }
            }
            if UserDefaults.standard.bool(forKey:"fullScreen") { DispatchQueue.main.async { self.window.toggleFullScreen(nil) } }
        }
        // --level n builds operation n (1-based) for the previews below; --cleared n opens the lobby with n cleared.
        if let index = CommandLine.arguments.firstIndex(of:"--level"), CommandLine.arguments.count > index+1, let n = Int(CommandLine.arguments[index+1]) {
            World.select(n-1); view.world.reset(); view.resetCamera()
        }
        if let index = CommandLine.arguments.firstIndex(of:"--cleared"), CommandLine.arguments.count > index+1, let n = Int(CommandLine.arguments[index+1]) { view.world.cleared = n }
        if CommandLine.arguments.contains("--preview") {
            view.inMenu = false; view.help = false
            view.world.spawn(4)
            view.world.attack(Vec(x:889,y:448))
        }
        if CommandLine.arguments.contains("--collapse-preview") {
            view.inMenu = false; view.help = false
            view.world.spawn(4)
            view.world.unit = World.scale; view.world.fill(108,48,44,7,0); view.world.unit = 1
            view.world.structureDirty = true
            for _ in 0..<35 { view.world.update(1.0/60) }
        }
        // --water-preview dam|splash|surface|drone|bridge [seconds] stages water scenes: at
        // Irongate Pass's reservoir the dam cut away so the lake pours out, a shell bursting on
        // the lake bed or at its surface, or a drone flown into the lake; or the Kessel bridge
        // blown down into the river.
        if let index = CommandLine.arguments.firstIndex(of:"--water-preview") {
            let args = CommandLine.arguments
            view.inMenu = false; view.help = false
            let mode = args.count > index+1 ? args[index+1] : "dam"
            World.select(mode == "bridge" ? 0 : 2); view.world.reset()
            let w = view.world, S = World.scale
            let seconds = args.count > index+2 ? Double(args[index+2]) ?? 3 : 3
            let lake = Double(705*S)*World.cell
            var bed = Double(64*S)*World.cell+World.top
            while w.material(at:Vec(x:lake,y:bed)) == 0 && bed < World.bottom { bed += World.cell }
            switch mode {
            case "splash": w.explode(at:Vec(x:lake,y:bed-3),radius:34)
            case "surface": w.explode(at:Vec(x:lake,y:Double(64*S)*World.cell+World.top+2),radius:34)
            case "drone":
                w.credits = 5_000; w.purchase(World.support[3],at:lake)
                for _ in 0..<900 where w.drone?.piloted != true { w.update(1.0/60) }
                w.steerDrone(toward:Vec(x:lake,y:w.drone?.position.y ?? 0))
                for _ in 0..<150 { w.update(1.0/60) }
                w.steerDrone(toward:Vec(x:lake,y:bed))
                for _ in 0..<900 where w.drone != nil { w.update(1.0/60) }
            case "bridge":
                for x in stride(from:266,through:314,by:6) { w.explode(at:Vec(x:Double(x*S)*World.cell,y:Double(World.bridgeDeck*S)*World.cell+World.top+4),radius:40) }
            default: w.unit = S; w.fill(756,40,30,50,0); w.unit = 1; w.structureDirty = true
            }
            for _ in 0..<Int(seconds*60) { w.update(1.0/60) }
            switch mode {
            case "dam": view.camera = Vec(x:6150,y:700); view.zoom = 1.1
            case "bridge": view.camera = Vec(x:Double(290*S)*World.cell,y:Double(75*S)*World.cell+World.top); view.zoom = 2
            case "drone": view.camera = w.wrecks.last.map{ Vec(x:$0.position.x,y:$0.position.y-40) } ?? Vec(x:lake,y:620); view.zoom = 3
            default: view.camera = Vec(x:lake,y:620); view.zoom = 1.6
            }
            view.clampCamera()
        }
        if CommandLine.arguments.contains("--debrief-preview") {
            view.inMenu = false; view.help = false
            view.world.spawn(4); view.world.score = World.requirement+1234
            view.world.objectives[1].destroyed = true
            view.extract()
        }
        if CommandLine.arguments.contains("--deploy-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.offers[2],at:300)
            view.deployMenu = true
        }
        if CommandLine.arguments.contains("--place-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.offers[0],at:200)
            view.placing = .troops(1); view.isHovering = true; view.pointer = view.toScreen(Vec(x:420,y:view.world.ground(at:420)-10))
        }
        if CommandLine.arguments.contains("--rpg-preview") {
            // Two RPG gunners selected and aiming at the bunker roof; --mixed adds a rifleman to the selection.
            view.inMenu = false; view.help = false
            view.world.spawn(2,kind:.rpg,at:420)
            if CommandLine.arguments.contains("--mixed") { view.world.spawn(1,at:470) }
            for _ in 0..<60 { view.world.update(1.0/60) }
            for i in view.world.soldiers.indices { view.world.soldiers[i].selected = true }
            view.camera = Vec(x:700,y:430); view.zoom = 1.2; view.clampCamera()
            view.isHovering = true; view.pointer = view.toScreen(Vec(x:980,y:300))
            view.world.faceRockets(toward:view.toWorld(view.pointer))
            if CommandLine.arguments.contains("--fire") { view.world.attack(view.toWorld(view.pointer)); for _ in 0..<20 { view.world.update(1.0/60) } }
        }
        if CommandLine.arguments.contains("--plane-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.support[0],at:900)
            while (view.world.planes.first?.x ?? 1e9) < 600 { view.world.update(1.0/60) }
            view.camera = Vec(x:590,y:(view.world.planes.first?.y ?? view.world.transportAltitude)+10); view.zoom = 3; view.clampCamera()
        }
        if CommandLine.arguments.contains("--strafe-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.support[1],at:1700)
            while (view.world.jets.first?.fired ?? 0) < World.gunRounds/2 { view.world.update(1.0/60) }
            for _ in 0..<4 { view.world.update(1.0/60) }
            let zoom = CommandLine.arguments.contains("--close") ? 3.0 : 1.1
            let jet = view.world.jets[0], y = jet.path.y
            view.camera = zoom > 2 ? Vec(x:jet.x,y:y) : Vec(x:1450,y:440); view.zoom = zoom; view.clampCamera()
        }
        // --firebomb-preview [seconds] calls a firebomb run on the town and lets it burn.
        if let index = CommandLine.arguments.firstIndex(of:"--firebomb-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.support[2],at:2750)
            let seconds = CommandLine.arguments.count > index+1 ? Double(CommandLine.arguments[index+1]) ?? 20 : 20
            for _ in 0..<Int(seconds*60) { view.world.update(1.0/60) }
            if CommandLine.arguments.contains("--wide") { view.camera = Vec(x:2500,y:330); view.zoom = 0.6 }
            else { view.camera = Vec(x:2760,y:330); view.zoom = 1.4 }
            view.clampCamera()
        }
        if CommandLine.arguments.contains("--firebomb-ghost") {
            view.inMenu = false; view.help = false
            view.camera = Vec(x:2600,y:380); view.zoom = 0.7; view.clampCamera()
            view.placing = .support(2); view.isHovering = true; view.pointer = view.toScreen(Vec(x:2750,y:450))
        }
        if CommandLine.arguments.contains("--strafe-ghost") {
            view.inMenu = false; view.help = false
            view.camera = Vec(x:3000,y:440); view.zoom = 0.8; view.clampCamera()
            view.placing = .support(1); view.isHovering = true; view.pointer = view.toScreen(Vec(x:3400,y:500))
        }
        if CommandLine.arguments.contains("--ammo-preview") {
            view.inMenu = false; view.help = false
            view.world.credits = 5_000
            view.world.purchase(World.offers[2],at:240); view.world.purchase(World.offers[1],at:420)
            view.world.purchase(World.offers[0],at:560)
            view.world.attack(Vec(x:889,y:448))
            for (i,ammo) in [0,7,40,25,0,2].enumerated() { view.world.soldiers[i].ammo = ammo }
            view.world.purchase(World.support[0],at:170)
            for _ in 0..<280 { view.world.update(1.0/60) }
            view.world.purchase(World.support[0],at:760)
            for _ in 0..<170 { view.world.update(1.0/60) }
            view.camera = Vec(x:560,y:400); view.zoom = 1.3; view.clampCamera()
            view.placing = .support(0); view.isHovering = true; view.pointer = view.toScreen(Vec(x:1000,y:500))
        }
        // --bank n and --withdraw n stock the lobby bank for screenshots.
        if let index = CommandLine.arguments.firstIndex(of:"--bank"), CommandLine.arguments.count > index+1, let n = Int(CommandLine.arguments[index+1]) { view.world.bank = n }
        if let index = CommandLine.arguments.firstIndex(of:"--withdraw"), CommandLine.arguments.count > index+1, let n = Int(CommandLine.arguments[index+1]) { view.withdrawal = n }
        if let index = CommandLine.arguments.firstIndex(of:"--speed"), CommandLine.arguments.count > index+1,
           let speed = Double(CommandLine.arguments[index+1]), World.speeds.contains(speed) { view.world.speed = speed }
        // --camera x,y,zoom frames any part of the level, e.g. 2880,700,0.25 for the whole front.
        if let index = CommandLine.arguments.firstIndex(of:"--camera"), CommandLine.arguments.count > index+1 {
            let v = CommandLine.arguments[index+1].split(separator:",").compactMap{Double($0)}
            if v.count == 3 {
                view.inMenu = false; view.help = false
                view.camera = Vec(x:v[0],y:v[1]); view.zoom = v[2]; view.clampCamera()
            }
        }
        // Overlay toggles for screenshots: the field guide, the expanded HVT list, the pause menu.
        if CommandLine.arguments.contains("--guide") { view.inMenu = false; view.help = true }
        if CommandLine.arguments.contains("--targets") { view.showTargets = true }
        if CommandLine.arguments.contains("--esc") { view.inMenu = false; view.openEscMenu() }
        if CommandLine.arguments.contains("--esc-settings") { view.inMenu = false; view.openEscMenu(); view.escPage = .settings }
        if CommandLine.arguments.contains("--esc-controls") { view.inMenu = false; view.openEscMenu(); view.escPage = .settings; view.settingsTab = .controls }
        // --rebind action shows the CONTROLS tab waiting for that action's new key.
        if let index = CommandLine.arguments.firstIndex(of:"--rebind"), CommandLine.arguments.count > index+1 { view.rebinding = KeyAction(rawValue:CommandLine.arguments[index+1]) }
        if CommandLine.arguments.contains("--esc-exit") { view.inMenu = false; view.openEscMenu(); view.escPage = .exit }
        // --lobby-settings [controls | danger [save|settings]] opens the lobby settings on a tab, or a danger confirmation.
        if let index = CommandLine.arguments.firstIndex(of:"--lobby-settings") {
            let rest = CommandLine.arguments.dropFirst(index+1)
            view.lobbySettings = true
            if rest.first == "danger" { view.settingsTab = .danger }
            if rest.first == "controls" { view.settingsTab = .controls }
            if rest.dropFirst().first == "save" { view.confirming = .deleteSave; view.confirmEntry = "DEL" }
            if rest.dropFirst().first == "settings" { view.confirming = .resetSettings; view.confirmEntry = "RESET" }
        }
        // --cheat text opens the lobby cheat box and types into it, for screenshots.
        if let index = CommandLine.arguments.firstIndex(of:"--cheat"), CommandLine.arguments.count > index+1 {
            view.cheatOpen = true; view.cheatType(CommandLine.arguments[index+1])
        }
        if let index = CommandLine.arguments.firstIndex(of:"--screenshot"), CommandLine.arguments.count > index+1 {
            let path = CommandLine.arguments[index+1]
            if CommandLine.arguments.contains("--preview") {
                for _ in 0..<210 { view.world.update(1.0/60) }
            }
            view.frame = NSRect(x:0,y:0,width:1440,height:900)
            let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:rep)
            try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu()
let root = NSMenuItem(); menu.addItem(root)
let appMenu = NSMenu(); root.submenu = appMenu
appMenu.addItem(withTitle:"About Raining Hell",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
appMenu.addItem(.separator())
appMenu.addItem(withTitle:"Hide Raining Hell",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
appMenu.addItem(withTitle:"Quit Raining Hell",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
let windowItem = NSMenuItem(); windowItem.title = "Window"; menu.addItem(windowItem)
let windowMenu = NSMenu(title:"Window"); windowItem.submenu = windowMenu
windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
app.windowsMenu = windowMenu
app.mainMenu = menu
let delegate = AppDelegate(); app.delegate = delegate
app.run()
