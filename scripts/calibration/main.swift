import Foundation
import CoreGraphics
import AppKit
func bytes(_ img: CGImage) throws -> [UInt8] {
 let ctx = try IconRenderer.context(img.width)
 ctx.draw(img,in:CGRect(x:0,y:0,width:img.width,height:img.height))
 return Array(UnsafeBufferPointer(start:ctx.data!.assumingMemoryBound(to: UInt8.self),count:img.width*img.height*4))
}
guard CommandLine.arguments.count > 1 else {
    print("Usage: calibrate sample-1024.png [output-directory]"); exit(1)
}
let outputRoot = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/validation")
try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
let native = try IconRenderer.load(URL(fileURLWithPath: CommandLine.arguments[1]))
guard native.width == 1024, native.height == 1024 else {
    print("Calibration needs a 1024 × 1024 opaque system app tile, with its original alpha."); exit(1)
}
print("Sample:", CommandLine.arguments[1])
print("Body alpha>128:", try IconRenderer.alphaBounds(native.image, threshold:128))
let target = try bytes(native.image)
let white = try IconRenderer.context(1024)
white.setFillColor(CGColor(gray:1,alpha:1));white.fill(CGRect(x:0,y:0,width:1024,height:1024))
let input = try IconSource(image:white.makeImage()!)
var best = (Double.greatestFiniteMagnitude,0.0,0.0,0.0)
for radius in [14.0,14.5,15,15.5,16,16.5,17] {
 for opacity in [0.22,0.23,0.24,0.25,0.26,0.27,0.28] {
  for offset in [8.0] {
   var settings=IconSettings();settings.shadowBlur=radius;settings.shadowOpacity=opacity;settings.shadowOffset=offset
   let rendered=try IconRenderer.render(input,settings:settings)
   let pixels=try bytes(rendered)
   var error=0.0
   // Sample straight edges away from the corners, where the baked artwork is opaque.
   for y in Array(40..<100)+Array(924..<984) {
    let i=(y*1024+512)*4+3
    error += pow(Double(pixels[i])-Double(target[i]),2)
   }
   if error < best.0 { best=(error,radius,opacity,offset) }
  }
 }
}
print("Best shadow fit (SSE, Gaussian radius, opacity, downward offset):",best)
var settings=IconSettings();settings.shadowBlur=best.1;settings.shadowOpacity=best.2;settings.shadowOffset=best.3
let output=try IconRenderer.render(input,settings:settings)
print("Rendered alpha>2",try IconRenderer.alphaBounds(output))
print("Native alpha>2",native.contentBounds)
try IconExporter.exportPNG(output,to:outputRoot.appendingPathComponent("calibrated-template.png"))

var shapeBest=(Int.max,0.0)
for radius in stride(from:180.0,through:224.0,by:2) {
 let mask=try IconRenderer.maskImage(in:CGRect(x:100,y:100,width:824,height:824),cornerRadiusFraction:radius/824)
 let pixels=try bytes(mask)
 var mismatch=0
 for i in stride(from:3,to:pixels.count,by:4) {
  if (pixels[i]>128) != (target[i]>128) { mismatch += 1 }
 }
 if mismatch<shapeBest.0 { shapeBest=(mismatch,radius) }
}
print("Best native continuous corner fit (pixel mismatch, radius):",shapeBest)

for file in CommandLine.arguments.dropFirst(3) {
 let other = try IconRenderer.load(URL(fileURLWithPath:file))
 let otherPixels = try bytes(other.image)
 guard otherPixels.count == target.count else { continue }
 var count=0
 for i in stride(from:3,to:target.count,by:4) { if target[i] != otherPixels[i] { count += 1 } }
 print("Alpha differences vs",file,":",count,"pixels")
}
