// PancakeNotch app-icon concepts — pure monochrome, drawn with CoreGraphics.
// The app's icon is concept 1, "Short Stack", re-rendered with an image model from this drawing
// (short-stack-source.png); make-icns.swift turns that into Resources/AppIcon.icns.
//
// Usage:
//   swift render.swift                      # render every concept: 1024 PNG + small-size sheet + comparison
//   swift render.swift --concept 2          # render one concept's 1024 PNG + sheet only
//   swift render.swift --iconset 2          # write concept2.iconset (all macOS sizes) and concept2.icns
//
// Output goes next to this script (or to --out <dir>).
// Design space is 1024x1024, y pointing DOWN. The squircle body is 824x824 at (100,100).

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Basics

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func G(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: sRGB, components: [v, v, v, a])! }
/// Gray from a single 0–255 byte, e.g. H(0x1C).
func H(_ b: Int, _ a: CGFloat = 1) -> CGColor { G(CGFloat(b) / 255, a) }

func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x + b.x, a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x - b.x, a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { P(a.x * k, a.y * k) }
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true); c.setShouldAntialias(true); c.interpolationQuality = .high
    return c
}

func savePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    precondition(CGImageDestinationFinalize(d), "could not write \(path)")
}

/// Drawing helper bound to one icon render. All coordinates are in 1024-space.
struct Pen {
    let ctx: CGContext
    let px: CGFloat                      // real pixel size of the icon being rendered
    var s: CGFloat { px / 1024 }
    var small: Bool { px <= 32 }         // simplified artwork for 16/32 px
    var tiny: Bool { px <= 16 }

    func shadow(dy: CGFloat, blur: CGFloat, _ c: CGColor) {
        // Shadow offset/blur live in device space (y up), so convert manually.
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: c)
    }
    func fill(_ p: CGPath, _ c: CGColor) { ctx.addPath(p); ctx.setFillColor(c); ctx.fillPath() }
    func fillEO(_ p: CGPath, _ c: CGColor) { ctx.addPath(p); ctx.setFillColor(c); ctx.fillPath(using: .evenOdd) }
    func linear(_ p: CGPath, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint) {
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    func radial(_ p: CGPath, _ g: CGGradient, _ c0: CGPoint, _ r0: CGFloat, _ c1: CGPoint, _ r1: CGFloat) {
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.drawRadialGradient(g, startCenter: c0, startRadius: r0, endCenter: c1, endRadius: r1,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    /// Paint a gradient along a stroke of `p` (used for rims / bevels). Clipped to `clip` if given.
    func strokeGradient(_ p: CGPath, width: CGFloat, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint, clip: CGPath? = nil) {
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip() }
        ctx.addPath(p); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    func clip(_ p: CGPath, _ body: () -> Void) {
        ctx.saveGState(); ctx.addPath(p); ctx.clip(); body(); ctx.restoreGState()
    }
    func layer(_ body: () -> Void) { ctx.saveGState(); body(); ctx.restoreGState() }
}

// MARK: - Shapes

/// Rounded rect with Apple-style continuous ("squircle") corners: each corner is a superellipse
/// quarter spread over 1.528·r, which has zero curvature where it meets the straight edges.
func squircle(_ r: CGRect, radius: CGFloat, n: CGFloat = 3.6) -> CGPath {
    let k = min(radius * 1.528665, min(r.width, r.height) / 2)
    let p = CGMutablePath()
    let steps = 90
    // corner centres (y-down), and the quadrant signs
    let corners: [(CGPoint, CGFloat, CGFloat, CGFloat)] = [
        (P(r.maxX - k, r.minY + k), 1, -1, 0),    // top-right   (angle runs 90°→0°)
        (P(r.maxX - k, r.maxY - k), 1, 1, 1),     // bottom-right (0°→-90°)
        (P(r.minX + k, r.maxY - k), -1, 1, 2),    // bottom-left
        (P(r.minX + k, r.minY + k), -1, -1, 3),   // top-left
    ]
    var first = true
    for (c, _, _, q) in corners {
        for i in 0...steps {
            // param t from 0..π/2 along the quarter, oriented clockwise on screen
            let t = CGFloat(i) / CGFloat(steps) * .pi / 2
            var ux: CGFloat, uy: CGFloat
            switch q {
            case 0: ux = sin(t); uy = -cos(t)        // from top edge to right edge
            case 1: ux = cos(t); uy = sin(t)         // right edge to bottom edge
            case 2: ux = -sin(t); uy = cos(t)        // bottom to left
            default: ux = -cos(t); uy = -sin(t)      // left to top
            }
            let e = 2 / n
            let x = c.x + k * (ux < 0 ? -1 : 1) * pow(abs(ux), e)
            let y = c.y + k * (uy < 0 ? -1 : 1) * pow(abs(uy), e)
            if first { p.move(to: P(x, y)); first = false } else { p.addLine(to: P(x, y)) }
        }
    }
    p.closeSubpath()
    return p
}

let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(bodyRect, radius: 185)

/// Quarter-ish round corner from the current point, bending around `via`, ending at `to`.
func corner(_ p: CGMutablePath, via c: CGPoint, to e: CGPoint, k: CGFloat = 0.62) {
    let s = p.currentPoint
    p.addCurve(to: e, control1: s + (c - s) * k, control2: e + (c - e) * k)
}

func pill(_ r: CGRect) -> CGPath { let k = min(r.width, r.height) / 2; return CGPath(roundedRect: r, cornerWidth: k, cornerHeight: k, transform: nil) }
/// True union of filled shapes (independent of each subpath's winding direction).
func merge(_ ps: [CGPath]) -> CGPath { ps.dropFirst().reduce(ps[0]) { $0.union($1) } }
func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil) }

/// MacBook-style notch hanging from y = top: straight sides, rounded bottom corners, and concave
/// "ears" where it meets the top edge. Extends far above `top` so it can be clipped by the body.
func notchPath(cx: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, rb: CGFloat, ear: CGFloat) -> CGMutablePath {
    let p = CGMutablePath()
    let L = cx - w / 2, R = cx + w / 2, B = top + h
    p.move(to: P(L - ear, top - 400))
    p.addLine(to: P(L - ear, top))
    corner(p, via: P(L, top), to: P(L, top + ear))
    p.addLine(to: P(L, B - rb))
    corner(p, via: P(L, B), to: P(L + rb, B))
    p.addLine(to: P(R - rb, B))
    corner(p, via: P(R, B), to: P(R, B - rb))
    p.addLine(to: P(R, top + ear))
    corner(p, via: P(R, top), to: P(R + ear, top))
    p.addLine(to: P(R + ear, top - 400))
    p.closeSubpath()
    return p
}

/// Polygon from a list of points (dense enough to look smooth).
func poly(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
}

func smax(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat {
    let h = max(k - abs(a - b), 0) / k
    return max(a, b) + h * h * k / 4
}

// MARK: - Shared icon body

enum Tone { case light, dark }

/// Draws the squircle body with drop shadow, vertical gradient and a soft top bevel.
func drawBody(_ p: Pen, top: CGColor, bottom: CGColor, tone: Tone) {
    p.layer {
        p.shadow(dy: 10, blur: 22, G(0, tone == .dark ? 0.45 : 0.32))
        p.fill(bodyPath, bottom)
    }
    p.linear(bodyPath, grad([(0, top), (1, bottom)]), P(512, 100), P(512, 924))
    // bevel: bright along the top rim fading out, slight dark along the bottom rim
    let hi: CGFloat = tone == .dark ? 0.30 : 0.95
    let lo: CGFloat = tone == .dark ? 0.35 : 0.10
    p.strokeGradient(bodyPath, width: p.small ? 0 : 7,
                     grad([(0, G(1, hi)), (0.35, G(1, 0)), (0.75, G(0, 0)), (1, G(0, lo))]),
                     P(512, 100), P(512, 924), clip: bodyPath)
}

// MARK: - Shared liquid shapes

/// Concave circular fillet profile: extra half-width at distance d below an edge, radius fr.
func fillet(_ d: CGFloat, _ fr: CGFloat) -> CGFloat {
    guard d < fr else { return 0 }
    return fr - sqrt(max(0, fr * fr - (fr - d) * (fr - d)))
}

/// Light catching the lower edge of a glossy shape: the shape minus itself shifted up by `offset`.
/// Pass a merged silhouette (see `merge`). `soft` builds a band that fades away from the edge.
func rimLight(_ p: Pen, _ shape: CGPath, offset: CGFloat, alpha: CGFloat, soft: Bool = false) {
    if soft {
        let steps = 6
        for i in 1...steps { rimLight(p, shape, offset: offset * CGFloat(i) / CGFloat(steps), alpha: alpha / CGFloat(steps) * 1.4) }
        return
    }
    p.clip(shape) {
        p.ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        p.fill(shape, G(1, alpha))
        p.ctx.setBlendMode(.destinationOut)
        p.ctx.translateBy(x: 0, y: -offset)
        p.fill(shape, G(0, 1))
        p.ctx.endTransparencyLayer()
    }
}

/// Vertical liquid "tongue" hanging from y = base: flared fillet at the top, slightly swelling body,
/// round tip. Total length `length`, tip half-width `w`.
func tongue(x: CGFloat, base: CGFloat, length: CGFloat, w: CGFloat, flare: CGFloat, fr: CGFloat = 14) -> CGPath {
    let y0 = base - 6, y1 = base + length
    let tipC = y1 - w
    let n = 260
    var L: [CGPoint] = [], R: [CGPoint] = []
    for i in 0...n {
        let u = CGFloat(i) / CGFloat(n)
        let y = y0 + (y1 - y0) * sin(u * .pi / 2)
        let d = max(y - base, 0)
        var hw = w * (0.84 + 0.16 * min(d / max(tipC - base, 1), 1)) + fillet(d, flare)
        if y > tipC { hw = w * sqrt(max(0, 1 - pow((y - tipC) / w, 2))) }
        L.append(P(x - hw, y)); R.append(P(x + hw, y))
    }
    return poly(L + R.reversed())
}

/// Soft elliptical specular glint on a glossy black blob of radius r centred at c.
func glint(_ p: Pen, c: CGPoint, r: CGFloat, alpha: CGFloat = 0.9) {
    p.layer {
        p.ctx.translateBy(x: c.x - r * 0.34, y: c.y - r * 0.40)
        p.ctx.rotate(by: -0.7)
        p.ctx.scaleBy(x: 1, y: 0.48)
        p.ctx.drawRadialGradient(grad([(0, G(1, alpha)), (0.45, G(1, alpha * 0.45)), (1, G(1, 0))]),
                                 startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.36, options: [])
    }
    // tiny hard catch-light
    p.fill(circle(P(c.x - r * 0.40, c.y - r * 0.44), r * 0.075), G(1, min(1, alpha + 0.1)))
}

/// Horizontal soft elliptical shadow (contact shadow on a surface).
func contactShadow(_ p: Pen, c: CGPoint, rx: CGFloat, ry: CGFloat, alpha: CGFloat) {
    p.layer {
        p.ctx.translateBy(x: c.x, y: c.y); p.ctx.scaleBy(x: 1, y: ry / rx)
        p.ctx.drawRadialGradient(grad([(0, G(0, alpha)), (0.6, G(0, alpha * 0.5)), (1, G(0, 0))]),
                                 startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
    }
}

// MARK: - Concept 1: Short Stack
// Side view of a pancake stack; the top "pancake" is the black Dynamic Island pill (camera dot and
// all), melting down the stack like syrup.

func concept1(_ p: Pen) {
    drawBody(p, top: H(0xFD), bottom: H(0xDC), tone: .light)
    p.clip(bodyPath) {
        let cx: CGFloat = 512
        let ph: CGFloat = p.small ? 126 : 98                // pancake thickness
        let overlap: CGFloat = p.small ? 6 : 10
        // (width, x-offset) from bottom to top
        let cakes: [(CGFloat, CGFloat)] = p.small ? [(664, 0), (640, 0)] : [(632, -8), (610, 11), (622, -3)]
        let islandW: CGFloat = p.small ? 560 : 486
        let islandH: CGFloat = p.small ? 150 : 116
        let sink: CGFloat = p.small ? 4 : 8                 // island sits slightly into the top pancake
        let stackH = CGFloat(cakes.count) * (ph - overlap) + overlap + islandH - sink
        let bottomY = 512 + stackH / 2 + (p.small ? 8 : 34)

        if !p.small { contactShadow(p, c: P(cx, bottomY - 2), rx: 360, ry: 26, alpha: 0.30) }

        var y = bottomY
        for (w, dx) in cakes {
            pancakeSide(p, CGRect(x: cx - w / 2 + dx, y: y - ph, width: w, height: ph))
            y = y - ph + overlap
        }
        let ir = CGRect(x: cx - islandW / 2, y: y - overlap - islandH + sink, width: islandW, height: islandH)
        var syrup: [CGPath] = [pill(ir)]
        if !p.small {
            // drips flowing from the island over the pancakes (x offset, length below island)
            for (dx, len, w) in [(-132.0, 84.0, 21.0), (-12.0, 178.0, 24.0), (118.0, 116.0, 22.0)] as [(CGFloat, CGFloat, CGFloat)] {
                syrup.append(tongue(x: cx + dx, base: ir.maxY - 2, length: len, w: w, flare: 22))
            }
        } else {
            syrup.append(tongue(x: cx - 30, base: ir.maxY - 2, length: 120, w: 34, flare: 30))
        }
        island(p, ir, shape: merge(syrup))
    }
}

func pancakeSide(_ p: Pen, _ r: CGRect) {
    let rad = r.height * 0.40
    let path = CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    p.layer { p.shadow(dy: 4, blur: 8, G(0, 0.40)); p.fill(path, H(0x90)) }
    // golden crust top & bottom (as grays) with crisp edges, pale fluffy crumb in the middle
    p.linear(path, grad([(0, H(0x6A)), (0.06, H(0x86)), (0.15, H(0xBC)), (0.24, H(0xD2)), (0.62, H(0xD6)), (0.80, H(0xBE)),
                         (0.89, H(0x98)), (1, H(0x60))]),
             P(0, r.minY), P(0, r.maxY))
    // rounded ends
    p.linear(path, grad([(0, G(0, 0.22)), (0.07, G(0, 0.02)), (0.5, G(0, 0)), (0.93, G(0, 0.02)), (1, G(0, 0.22))]),
             P(r.minX, 0), P(r.maxX, 0))
    if !p.small {
        p.strokeGradient(path, width: 4, grad([(0, G(1, 0.5)), (0.25, G(1, 0)), (1, G(1, 0))]), P(0, r.minY), P(0, r.maxY), clip: path)
    }
}

/// Glossy black island. `shape` is the full black silhouette (island + any drips).
func island(_ p: Pen, _ r: CGRect, shape: CGPath) {
    p.layer { p.shadow(dy: 6, blur: 12, G(0, 0.35)); p.fill(shape, H(0x00)) }
    p.linear(shape, grad([(0, H(0x34)), (0.12, H(0x14)), (0.5, H(0x05)), (1, H(0x10))]), P(0, r.minY), P(0, r.maxY))
    if !p.small {
        // broad top reflection on the pill
        let gr = CGRect(x: r.minX + 34, y: r.minY + 10, width: r.width - 68, height: r.height * 0.34)
        p.linear(pill(gr), grad([(0, G(1, 0.22)), (1, G(1, 0.0))]), P(0, gr.minY), P(0, gr.maxY))
        // thin rim light along all lower edges (drips included)
        rimLight(p, shape, offset: 5, alpha: 0.22)
    }
    // camera lens on the right
    let lc = P(r.maxX - r.height / 2 - (p.small ? 6 : 4), r.midY)
    let lr = r.height * (p.small ? 0.22 : 0.19)
    p.radial(circle(lc, lr), grad([(0, H(0x30)), (0.55, H(0x1A)), (0.8, H(0x0C)), (1, H(0x44))]), P(lc.x + lr * 0.2, lc.y + lr * 0.2), 0, lc, lr)
    if !p.small {
        p.fill(circle(P(lc.x - lr * 0.30, lc.y - lr * 0.32), lr * 0.20), G(1, 0.60))
    }
}

// MARK: - Concept 2: Syrup Drip
// White squircle; the black notch at the top edge drips a glossy drop of "syrup".

func concept2(_ p: Pen) {
    drawBody(p, top: H(0xFF), bottom: H(0xE0), tone: .light)
    p.clip(bodyPath) {
        let top: CGFloat = 100
        let nw: CGFloat = p.small ? 440 : 380
        let nh: CGFloat = p.small ? 176 : 150
        let notch = notchPath(cx: 512, top: top, w: nw, h: nh, rb: p.small ? 70 : 62, ear: p.small ? 24 : 32)
        let dx: CGFloat = p.small ? 512 : 548               // drip x (a little off-centre)
        let base = top + nh
        let bulbR: CGFloat = p.small ? 100 : 70
        let bulbC: CGFloat = p.small ? base + 180 : base + 196
        let drip = dripPath(x: dx, base: base, bulbC: bulbC, bulbR: bulbR, neck: p.small ? 40 : 24,
                            flare: p.small ? 44 : 40, neckEnd: p.small ? base + 90 : base + 110)
        var parts: [CGPath] = [notch, drip]

        var dropC: CGPoint? = nil
        if !p.small {
            let d = teardrop(cx: dx, top: bulbC + bulbR + 78, r: 52, length: 176)
            parts.append(d)
            dropC = P(dx, d.boundingBox.maxY - 52)
        }
        let all = merge(parts)

        // soft shadow of the syrup on the white "screen"
        p.layer { p.shadow(dy: 12, blur: 26, G(0, 0.26)); p.fill(all, H(0x00)) }
        // glossy black, lifted slightly toward the lower edges
        p.linear(all, grad([(0, H(0x00)), (0.55, H(0x08)), (1, H(0x22))]), P(0, top), P(0, 860))
        if !p.small {
            // rim light hugging the lower contour of every blob
            rimLight(p, all, offset: 10, alpha: 0.16, soft: true)
            glint(p, c: P(dx, bulbC + 4), r: bulbR)
            if let dropC { glint(p, c: dropC, r: 54) }
        } else {
            p.fill(circle(P(dx - bulbR * 0.36, bulbC - bulbR * 0.30), bulbR * 0.20), G(1, 0.75))
        }
    }
}

/// Liquid strand from the notch's bottom edge into a hanging, slightly pear-shaped bulb.
/// Built from beziers: fillet out of the edge, a narrow strand down to `neckEnd`, then a smooth
/// swell into a round bulb (widest at bulbC) and a semicircular bottom.
func dripPath(x: CGFloat, base: CGFloat, bulbC: CGFloat, bulbR: CGFloat, neck: CGFloat, flare: CGFloat, neckEnd: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let swell = bulbR * 0.95
    p.move(to: P(x - neck - flare, base - 10))
    p.addLine(to: P(x - neck - flare, base))
    corner(p, via: P(x - neck, base), to: P(x - neck, base + flare), k: 0.56)
    p.addCurve(to: P(x - bulbR, bulbC), control1: P(x - neck * 0.92, neckEnd), control2: P(x - bulbR, bulbC - swell))
    // bottom half of the bulb: left → bottom → right (angles π → π/2 → 0 in y-down space)
    var a: CGFloat = .pi
    while a > 0 { a -= .pi / 90; p.addLine(to: P(x + bulbR * cos(max(a, 0)), bulbC + bulbR * sin(max(a, 0)))) }
    p.addCurve(to: P(x + neck, base + flare), control1: P(x + bulbR, bulbC - swell), control2: P(x + neck * 0.92, neckEnd))
    corner(p, via: P(x + neck, base), to: P(x + neck + flare, base), k: 0.56)
    p.addLine(to: P(x + neck + flare, base - 10))
    p.closeSubpath()
    return p
}

/// Falling drop: pointed top, round bottom.
func teardrop(cx: CGFloat, top: CGFloat, r: CGFloat, length: CGFloat) -> CGPath {
    var pts: [CGPoint] = []
    let n = 300
    for i in 0..<(2 * n) {
        let t = CGFloat(i) / CGFloat(n) * .pi
        let side: CGFloat = t <= .pi ? 1 : -1
        let tt = t <= .pi ? t : 2 * .pi - t
        // pow < 1 gives a fuller body with a crisp but short tip
        let xx = r * sin(tt) * pow(sin(tt / 2), 1.25) * side * 1.08
        let yy = top + length * (1 - cos(tt)) / 2
        pts.append(P(cx + xx, yy))
    }
    return poly(pts)
}

// MARK: - Concept 3: Ripple (notch expanding into an island)
// Dark "screen"; a bright island hangs from the top edge, with fading echoes of its expanded states.

func concept3(_ p: Pen) {
    drawBody(p, top: H(0x30), bottom: H(0x0A), tone: .dark)
    p.clip(bodyPath) {
        let top: CGFloat = 100
        let echoes: [(w: CGFloat, h: CGFloat, rb: CGFloat, a: CGFloat)] = p.small
            ? [(700, 560, 190, 0.50)]
            : [(720, 652, 210, 0.16), (612, 486, 160, 0.32), (512, 334, 116, 0.56)]
        let widths: [CGFloat] = p.small ? [46] : [16, 20, 24]
        for (i, e) in echoes.enumerated() {
            let path = notchPath(cx: 512, top: top, w: e.w, h: e.h, rb: e.rb, ear: 30)
            // each echo fades out toward the top so it never collides with the icon's corners
            p.strokeGradient(path, width: widths[i], grad([(0, G(1, 0)), (0.50, G(1, 0)), (0.86, G(1, e.a)), (1, G(1, e.a))]),
                             P(0, top), P(0, top + e.h), clip: bodyPath)
        }
        // the solid island
        let nw: CGFloat = p.small ? 480 : 412, nh: CGFloat = p.small ? 300 : 182
        let isl = notchPath(cx: 512, top: top, w: nw, h: nh, rb: p.small ? 104 : 76, ear: 30)
        p.layer { p.shadow(dy: 10, blur: 40, G(1, 0.22)); p.fill(isl, H(0xF4)) }
        p.linear(isl, grad([(0, H(0xFF)), (0.6, H(0xF2)), (1, H(0xD4))]), P(0, top), P(0, top + nh))
        if !p.small {
            // equalizer bars = something is playing
            let bars: [CGFloat] = [0.42, 0.80, 0.58, 1.0, 0.50]
            let bw: CGFloat = 22, gap: CGFloat = 15
            let total = CGFloat(bars.count) * bw + CGFloat(bars.count - 1) * gap
            let midY = top + nh * 0.55, maxH: CGFloat = 84
            for (i, b) in bars.enumerated() {
                let h = max(maxH * b, bw)
                p.fill(pill(CGRect(x: 512 - total / 2 + CGFloat(i) * (bw + gap), y: midY - h / 2, width: bw, height: h)), H(0x16))
            }
        }
    }
}

// MARK: - Concept 4: Notch Bite
// Top-down pancake stack (with a pat of butter) that has a notch bitten out of its top edge.

/// Tiny deterministic RNG so the pancake texture is identical on every render.
struct LCG {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 100_000) / 100_000
    }
}

func concept4(_ p: Pen) {
    drawBody(p, top: H(0x2E), bottom: H(0x07), tone: .dark)
    p.clip(bodyPath) {
        let R: CGFloat = p.small ? 330 : 300
        let c = P(512, p.small ? 494 : 474)
        let hw: CGFloat = p.small ? 124 : 104        // half width of the cut
        let depth: CGFloat = p.small ? 160 : 142     // cut depth from the disc's top
        let rf: CGFloat = p.small ? 26 : 22
        // pancakes underneath, peeking out below (pale sides, dark gaps)
        let layers: [CGFloat] = p.small ? [30] : [56, 28]
        for dy in layers {
            let path = bittenDisc(c: P(c.x, c.y + dy), R: R, hw: hw, depth: depth, rf: rf)
            p.layer { p.shadow(dy: 4, blur: 10, G(0, 0.6)); p.fill(path, H(0xB4)) }
            p.linear(path, grad([(0, H(0xE6)), (0.80, H(0xD0)), (0.94, H(0xB0)), (1, H(0x84))]), P(0, c.y - R + dy), P(0, c.y + R + dy))
        }
        let topDisc = bittenDisc(c: c, R: R, hw: hw, depth: depth, rf: rf)
        p.layer { p.shadow(dy: 3, blur: 8, G(0, 0.45)); p.fill(topDisc, H(0xB0)) }
        // golden-brown face as grays: evenly browned middle, pale ring, crisp edge
        p.radial(topDisc, grad([(0, H(0xB2)), (0.70, H(0xBA)), (0.80, H(0xC6)), (0.88, H(0xDE)), (0.95, H(0xF0)), (0.985, H(0xE6)), (1, H(0xC0))]),
                 c, 0, c, R)
        if !p.small {
            p.linear(topDisc, grad([(0, G(1, 0.20)), (0.5, G(1, 0)), (1, G(0, 0.10))]), P(c.x - R, c.y - R), P(c.x + R, c.y + R))
            p.strokeGradient(topDisc, width: 4, grad([(0, G(1, 0.8)), (1, G(1, 0.25))]), P(0, c.y - R), P(0, c.y + R), clip: topDisc)
        }
        // glossy black syrup pool with a pat of butter on top (dropped at 16 px: just the bitten pancake)
        if p.tiny { return }
        let pc = P(c.x - 4, c.y + (p.small ? 40 : 46))
        let pr: CGFloat = p.small ? 168 : 132
        let syrup = blob(c: pc, r: pr)
        p.layer { p.shadow(dy: 5, blur: 10, G(0, 0.30)); p.fill(syrup, H(0x00)) }
        p.linear(syrup, grad([(0, H(0x22)), (0.5, H(0x06)), (1, H(0x12))]), P(0, pc.y - pr), P(0, pc.y + pr))
        if !p.small {
            rimLight(p, syrup, offset: 9, alpha: 0.20, soft: true)
            glint(p, c: P(pc.x - 34, pc.y + 6), r: pr * 0.8, alpha: 0.7)
        }
        butter(p, c: P(pc.x + (p.small ? 0 : 14), pc.y - (p.small ? 4 : 10)), size: p.small ? 150 : 112, angle: -0.22)
    }
}

/// Organic, slightly wobbly round puddle.
func blob(c: CGPoint, r: CGFloat) -> CGPath {
    var pts: [CGPoint] = []
    for i in 0..<360 {
        let t = CGFloat(i) / 360 * 2 * .pi
        let rr = r * (1 + 0.045 * sin(2 * t + 0.4) + 0.035 * sin(3 * t + 1.7) + 0.015 * sin(5 * t + 0.3))
        pts.append(P(c.x + rr * cos(t), c.y + rr * 0.94 * sin(t)))
    }
    return poly(pts)
}

func butter(_ p: Pen, c: CGPoint, size: CGFloat, angle: CGFloat) {
    p.layer {
        p.ctx.translateBy(x: c.x, y: c.y); p.ctx.rotate(by: angle)
        let r = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let rr = size * 0.20
        let thick = p.small ? 0 : size * 0.12
        let side = CGPath(roundedRect: r.offsetBy(dx: 0, dy: thick), cornerWidth: rr, cornerHeight: rr, transform: nil)
        let face = CGPath(roundedRect: r, cornerWidth: rr, cornerHeight: rr, transform: nil)
        p.layer { p.shadow(dy: 8, blur: 16, G(0, 0.30)); p.fill(side, H(0xC4)) }
        if !p.small {
            p.linear(side, grad([(0, H(0xE4)), (1, H(0xB4))]), P(0, 0), P(0, size / 2 + thick))
        }
        p.linear(face, grad([(0, H(0xFF)), (1, H(0xEE))]), P(-size / 2, -size / 2), P(size / 2, size / 2))
        if !p.small {
            p.strokeGradient(face, width: 3, grad([(0, G(1, 1)), (1, G(0, 0.05))]), P(0, -size / 2), P(0, size / 2), clip: face)
        }
    }
}


/// Disc of radius R with a notch-shaped cut from its top: cut half-width `hw`, depth `depth`
/// (measured from the disc's topmost point). Corners where the cut meets the rim are rounded.
func bittenDisc(c: CGPoint, R: CGFloat, hw: CGFloat, depth: CGFloat, rf: CGFloat = 22, rb: CGFloat = 44) -> CGPath {
    let fx = c.x - hw - rf
    let fy = c.y - sqrt(pow(R - rf, 2) - pow(fx - c.x, 2))
    let ang = atan2(fy - c.y, fx - c.x)
    let tangentRim = P(c.x + R * cos(ang), c.y + R * sin(ang))
    let p = CGMutablePath()
    let B = c.y - R + depth
    p.move(to: tangentRim)
    let angR = .pi - ang
    p.addArc(center: c, radius: R, startAngle: ang, endAngle: angR + 2 * .pi, clockwise: true)
    let fxr = c.x + hw + rf
    p.addArc(center: P(fxr, fy), radius: rf, startAngle: angR, endAngle: .pi, clockwise: true)
    p.addLine(to: P(c.x + hw, B - rb))
    corner(p, via: P(c.x + hw, B), to: P(c.x + hw - rb, B), k: 0.56)
    p.addLine(to: P(c.x - hw + rb, B))
    corner(p, via: P(c.x - hw, B), to: P(c.x - hw, B - rb), k: 0.56)
    p.addLine(to: P(c.x - hw, fy))
    p.addArc(center: P(fx, fy), radius: rf, startAngle: 0, endAngle: ang, clockwise: true)
    p.closeSubpath()
    return p
}

// MARK: - Rendering

let concepts: [Int: (name: String, draw: (Pen) -> Void)] = [
    1: ("Short Stack", concept1),
    2: ("Syrup Drip", concept2),
    3: ("Ripple", concept3),
    4: ("Notch Bite", concept4),
]

func renderIcon(_ n: Int, px: Int) -> CGImage {
    let ctx = makeContext(px, px)
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: s, y: -s)
    let pen = Pen(ctx: ctx, px: CGFloat(px))
    concepts[n]!.draw(pen)
    // hairline edge so artwork touching the rim (the notch) still has a defined silhouette
    pen.clip(bodyPath) {
        ctx.addPath(bodyPath); ctx.setLineWidth(max(3, 2 / pen.s)); ctx.setStrokeColor(G(0, 0.10)); ctx.strokePath()
    }
    return ctx.makeImage()!
}

func drawText(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor,
              center: Bool = true, bold: Bool = false) {
    let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
    let attr = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = P(center ? x - w / 2 : x, y)
    CTLineDraw(line, ctx)
}

/// 16/32/64/128 at 1:1 plus pixel-zoomed 16 and 32, on light and dark rows.
func previewSheet(_ n: Int) -> CGImage {
    let sizes = [16, 32, 64, 128]
    let imgs = sizes.map { renderIcon(n, px: $0) }
    let pad: CGFloat = 28, gap: CGFloat = 36, rowH: CGFloat = 128 + 2 * pad + 22
    let zoom: CGFloat = 128
    let W = pad * 2 + CGFloat(sizes.reduce(0, +)) + 2 * zoom + gap * 5
    let Hh = rowH * 2 + 40
    let ctx = makeContext(Int(W), Int(Hh))
    ctx.setFillColor(H(0xFF)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: Hh))
    drawText(ctx, "\(n) · \(concepts[n]!.name) — actual pixels (left) and magnified 16 / 32 (right)",
             x: pad, y: Hh - 26, size: 13, color: H(0x44), center: false, bold: true)
    for (row, bg) in [(0, H(0xF2)), (1, H(0x1E))].reversed() {
        let y0 = CGFloat(row) * rowH
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y0, width: W, height: rowH))
        let fg = row == 1 ? H(0x9A) : H(0x70)
        var x = pad
        let baseY = y0 + pad + 22
        for (i, img) in imgs.enumerated() {
            let sz = CGFloat(sizes[i])
            ctx.interpolationQuality = .none
            ctx.draw(img, in: CGRect(x: x, y: baseY + (128 - sz) / 2, width: sz, height: sz))
            drawText(ctx, "\(sizes[i])", x: x + sz / 2, y: y0 + pad - 6, size: 11, color: fg)
            x += sz + gap
        }
        for (img, label) in [(imgs[0], "16 ×8"), (imgs[1], "32 ×4")] {
            ctx.interpolationQuality = .none
            ctx.draw(img, in: CGRect(x: x, y: baseY, width: zoom, height: zoom))
            drawText(ctx, label, x: x + zoom / 2, y: y0 + pad - 6, size: 11, color: fg)
            x += zoom + gap
        }
    }
    return ctx.makeImage()!
}

func comparison() -> CGImage {
    // two bands (light desktop / dark desktop), 4 icons each at 256 px, labels underneath
    let cell: CGFloat = 256, pad: CGFloat = 48, gap: CGFloat = 40, band: CGFloat = cell + 2 * 36
    let W = pad * 2 + cell * 4 + gap * 3, Hh: CGFloat = 60 + band * 2 + 56
    let ctx = makeContext(Int(W), Int(Hh))
    ctx.setFillColor(H(0xFF)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: Hh))
    drawText(ctx, "PancakeNotch — icon concepts", x: W / 2, y: Hh - 38, size: 20, color: H(0x22), bold: true)
    let bands: [(CGFloat, CGGradient)] = [
        (Hh - 60 - band, grad([(0, H(0xF4)), (1, H(0xE4))])),
        (Hh - 60 - band * 2, grad([(0, H(0x2A)), (1, H(0x16))])),
    ]
    for (y, g) in bands {
        ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: y, width: W, height: band))
        ctx.drawLinearGradient(g, start: P(0, y + band), end: P(0, y), options: []); ctx.restoreGState()
    }
    for n in 1...4 {
        let x = pad + CGFloat(n - 1) * (cell + gap)
        let img = renderIcon(n, px: 256)
        for (y, _) in bands { ctx.draw(img, in: CGRect(x: x, y: y + 36, width: cell, height: cell)) }
        drawText(ctx, "\(n)  \(concepts[n]!.name)", x: x + cell / 2, y: 22, size: 17, color: H(0x33), bold: true)
    }
    return ctx.makeImage()!
}

func writeIconset(_ n: Int, dir outDir: String) {
    let set = "\(outDir)/concept\(n).iconset"
    try? FileManager.default.removeItem(atPath: set)
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        savePNG(renderIcon(n, px: base), "\(set)/icon_\(base)x\(base).png")
        savePNG(renderIcon(n, px: base * 2), "\(set)/icon_\(base)x\(base)@2x.png")
    }
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    t.arguments = ["-c", "icns", set, "-o", "\(outDir)/concept\(n).icns"]
    try! t.run(); t.waitUntilExit()
    print(t.terminationStatus == 0 ? "wrote \(set) and \(outDir)/concept\(n).icns" : "iconutil failed (\(t.terminationStatus))")
}

// MARK: - CLI

var args = Array(CommandLine.arguments.dropFirst())
var outDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
var only: Int? = nil
var iconset: Int? = nil
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": outDir = args.removeFirst()
    case "--concept": only = Int(args.removeFirst())
    case "--iconset": iconset = Int(args.removeFirst())
    default: print("unknown argument \(a)"); exit(2)
    }
}

if let n = iconset {
    writeIconset(n, dir: outDir)
} else {
    for n in (only.map { [$0] } ?? [1, 2, 3, 4]) {
        savePNG(renderIcon(n, px: 1024), "\(outDir)/concept\(n)_1024.png")
        savePNG(previewSheet(n), "\(outDir)/concept\(n)_sizes.png")
        print("concept \(n) done")
    }
    if only == nil { savePNG(comparison(), "\(outDir)/comparison.png"); print("comparison done") }
}
