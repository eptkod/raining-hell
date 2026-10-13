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
    check(w.speed == 1,"speed cycles 4x back to 1x")
    w.cease()
    check(w.soldiers.allSatisfy{$0.target == nil},"cease fire clears all orders")
    let x = w.soldiers[0].position.x
    w.move(400)
    for _ in 0..<60 { w.update(1/60) }
    check(w.soldiers[0].position.x > x,"move command advances soldiers")
    for _ in 0..<12 { w.spawn(4) }
    check(w.soldiers.count == 32,"unit cap enforced")
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
            view.camera = Vec(x:590,y:World.planeAltitude+10); view.zoom = 3; view.clampCamera()
        }
        if CommandLine.arguments.contains("--strafe-preview") {
            view.inMenu = false; view.help = false
            view.world.purchase(World.support[1],at:1700)
            while (view.world.jets.first?.fired ?? 0) < World.gunRounds/2 { view.world.update(1.0/60) }
            for _ in 0..<4 { view.world.update(1.0/60) }
            let zoom = CommandLine.arguments.contains("--close") ? 3.0 : 1.1
            let jet = view.world.jets[0], y = World.strafePath(jet.dx,low:jet.low).y
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
           let speed = Int(CommandLine.arguments[index+1]), World.speeds.contains(speed) { view.world.speed = speed }
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
        if CommandLine.arguments.contains("--esc-exit") { view.inMenu = false; view.openEscMenu(); view.escPage = .exit }
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
