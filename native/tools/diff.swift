// Compares the native snapshot with the web reference (cropped to the window), pixel by pixel.
//   diff ref.png native.png out-diff.png cropX cropY
import AppKit
func rgba(_ p: String) -> (w: Int, h: Int, d: [UInt8]) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height; var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return (w, h, d)
}
let a = CommandLine.arguments
let ref = rgba(a[1]), nat = rgba(a[2]); let ox = Int(a[4])!, oy = Int(a[5])!
let w = nat.w, h = nat.h
var out = [UInt8](repeating: 255, count: w * h * 4)
var bad = 0, worst = 0, rows = [Int](repeating: 0, count: h)
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4, j = ((y + oy) * ref.w + (x + ox)) * 4
    let d = max(abs(Int(ref.d[j]) - Int(nat.d[i])), abs(Int(ref.d[j+1]) - Int(nat.d[i+1])), abs(Int(ref.d[j+2]) - Int(nat.d[i+2])))
    worst = max(worst, d)
    if d > 24 { bad += 1; rows[y] += 1; out[i] = 255; out[i+1] = 40; out[i+2] = 40 }
    else { let g = UInt8(Double(nat.d[i]) * 0.35); out[i] = g; out[i+1] = g; out[i+2] = g }
}}
let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[3]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil); CGImageDestinationFinalize(dst)
print(String(format: "differing pixels (>24/255): %d of %d (%.3f%%), worst %d", bad, w * h, Double(bad) / Double(w * h) * 100, worst))
var bands: [String] = []; var s = -1
for y in 0..<h { if rows[y] > 2 { if s < 0 { s = y } } else if s >= 0 { bands.append("\(s)-\(y - 1)"); s = -1 } }
print("rows with differences:", bands.prefix(40).joined(separator: " "))
