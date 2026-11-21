// Prints the ink box (bounds of bright pixels) of named regions in the reference and the native snapshot.
//   ink ref.png native.png cropX cropY  name:x,y,w,h ...
import AppKit
func rgba(_ p: String) -> (w: Int, h: Int, d: [UInt8]) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height; var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return (w, h, d)
}
let a = CommandLine.arguments, ref = rgba(a[1]), nat = rgba(a[2]), ox = Int(a[3])!, oy = Int(a[4])!
func box(_ im: (w: Int, h: Int, d: [UInt8]), _ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ dx: Int, _ dy: Int) -> String {
    var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, sum = 0
    // background = the region's darkest corner; ink = anything 60+ brighter
    for y in y0..<(y0 + h) { for x in x0..<(x0 + w) {
        let i = ((y + dy) * im.w + (x + dx)) * 4; let l = (Int(im.d[i]) + Int(im.d[i+1]) + Int(im.d[i+2])) / 3
        if l > 90 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); sum += l }
    }}
    return maxX < 0 ? "none" : "x\(minX)-\(maxX) y\(minY)-\(maxY) ink\(sum / 1000)"
}
for spec in a.dropFirst(5) {
    let p = spec.split(separator: ":"), n = p[1].split(separator: ",").map { Int($0)! }
    print(p[0].padding(toLength: 12, withPad: " ", startingAt: 0), "web", box(ref, n[0], n[1], n[2], n[3], ox, oy), "| native", box(nat, n[0], n[1], n[2], n[3], 0, 0))
}
