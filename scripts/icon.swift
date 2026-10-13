import AppKit
let root = CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath:root,withIntermediateDirectories:true)
func col(_ h:UInt32)->NSColor { NSColor(calibratedRed:Double(h>>16&255)/255,green:Double(h>>8&255)/255,blue:Double(h&255)/255,alpha:1) }
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let context = NSGraphicsContext(bitmapImageRep:rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let ctx = context.cgContext; ctx.scaleBy(x:Double(size)/1024,y:Double(size)/1024)
    col(0x13272f).setFill(); NSBezierPath(roundedRect:NSRect(x:30,y:30,width:964,height:964),xRadius:208,yRadius:208).fill()
    func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ c:UInt32) { col(c).setFill(); NSRect(x:x,y:y,width:w,height:h).fill() }
    box(146,185,730,58,0x5b7167)
    for i in 0..<12 { box(150+Double(i)*60,128,51,48,0x344d4e) }
    // A block-built falling shell over an explosive orange breach.
    let flame = NSBezierPath(); flame.move(to:NSPoint(x:290,y:252)); flame.line(to:NSPoint(x:355,y:475)); flame.line(to:NSPoint(x:456,y:389)); flame.line(to:NSPoint(x:555,y:623)); flame.line(to:NSPoint(x:645,y:411)); flame.line(to:NSPoint(x:748,y:452)); flame.line(to:NSPoint(x:705,y:252)); flame.close(); col(0xe9a566).setFill(); flame.fill()
    box(421,244,173,116,0xffd296)
    ctx.saveGState(); ctx.translateBy(x:574,y:703); ctx.rotate(by:-0.38)
    box(-68,-103,136,207,0xc8d3bd); box(-68,64,136,39,0x6c857b); box(-91,98,43,73,0xc8d3bd); box(48,98,43,73,0xc8d3bd); box(-37,-137,74,35,0xe9a566)
    ctx.restoreGState()
    box(230,567,25,85,0x567578); box(760,654,25,88,0x567578); box(340,780,25,76,0x567578)
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using:.png,properties:[:])!
    let names: [String]
    switch size {
    case 16: names=["icon_16x16.png"]
    case 32: names=["icon_16x16@2x.png","icon_32x32.png"]
    case 64: names=["icon_32x32@2x.png"]
    case 128: names=["icon_128x128.png"]
    case 256: names=["icon_128x128@2x.png","icon_256x256.png"]
    case 512: names=["icon_256x256@2x.png","icon_512x512.png"]
    default: names=["icon_512x512@2x.png"]
    }
    for name in names { try! data.write(to:URL(fileURLWithPath:root+"/"+name)) }
}
