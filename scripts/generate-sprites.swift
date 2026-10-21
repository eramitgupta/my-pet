#!/usr/bin/env swift
// Generates the bundled pixel-art pets: sprite strips, tint masks and manifests.
//
//   swift scripts/generate-sprites.swift [output-dir] [--preview preview.png]
//
// Default output: macos/mypet/Assets/Pets. The PNGs are committed, so this only needs to
// run when the art changes.
//
// How the art is built: each frame is drawn from simple shapes (ellipses, thick lines,
// triangles) into a *material* grid. Materials are then turned into pixel colours with
// automatic shading (top edge highlight, bottom edge shade) and a 1-pixel outline. Small
// details (eyes, noses, collars, z's) are painted on top. Tintable materials are neutral
// greys so the app can multiply them with the memory-gradient colour; the mask PNG marks
// exactly those pixels.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 32, H = 32
let ground = 28.5 // centre y of the lowest leg pixel row (row 29); outline sits on row 30

// MARK: - Palette

enum Ink: UInt8 {
    case clear = 0, outline, base, shade, light, far, eye, glint, pink, dark, darkShade, cream, zzz, collar, tooth
    var rgba: (UInt8, UInt8, UInt8, UInt8) {
        switch self {
        case .clear: return (0, 0, 0, 0)
        case .outline: return (0x2A, 0x22, 0x30, 255)
        case .base: return (0xDB, 0xDB, 0xDB, 255)
        case .shade: return (0xAA, 0xAA, 0xAA, 255)
        case .light: return (0xFF, 0xFF, 0xFF, 255)
        case .far: return (0x94, 0x94, 0x94, 255)
        case .eye: return (0x1B, 0x16, 0x22, 255)
        case .glint: return (0xFF, 0xFF, 0xFF, 255)
        case .pink: return (0xF2, 0x9B, 0xB2, 255)
        case .dark: return (0x3A, 0x35, 0x40, 255)
        case .darkShade: return (0x27, 0x23, 0x2C, 255)
        case .cream: return (0xF7, 0xEC, 0xDA, 255)
        case .zzz: return (0x6A, 0xA8, 0xFF, 255)
        case .collar: return (0xE5, 0x48, 0x4D, 255)
        case .tooth: return (0xFF, 0xFF, 0xFF, 255)
        }
    }
    /// Pixels the app recolours with the gradient.
    var tinted: Bool { self == .base || self == .shade || self == .light || self == .far }
}

enum Mat: UInt8 { case none = 0, body, far, dark, cream, pink }

// MARK: - Canvas

struct Canvas {
    var mat = [Mat](repeating: .none, count: W * H)
    var ink = [Ink](repeating: .clear, count: W * H)
    var detail = [Ink?](repeating: nil, count: W * H)

    func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H }

    mutating func plot(_ x: Int, _ y: Int, _ m: Mat) {
        if inside(x, y) { mat[y * W + x] = m }
    }

    func matAt(_ x: Int, _ y: Int) -> Mat { inside(x, y) ? mat[y * W + x] : .none }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ m: Mat) {
        guard rx > 0, ry > 0 else { return }
        for y in max(0, Int(cy - ry) - 1)...min(H - 1, Int(cy + ry) + 1) {
            for x in max(0, Int(cx - rx) - 1)...min(W - 1, Int(cx + rx) + 1) {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 { plot(x, y, m) }
            }
        }
    }

    mutating func circle(_ cx: Double, _ cy: Double, _ r: Double, _ m: Mat) { ellipse(cx, cy, r, r, m) }

    /// Thick line with round caps; thickness may taper from t0 to t1.
    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ t0: Double, _ t1: Double? = nil, _ m: Mat) {
        let len = max(1.0, hypot(x1 - x0, y1 - y0))
        let steps = Int(len * 4)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let r = (t0 + ((t1 ?? t0) - t0) * t) / 2
            circle(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, max(r, 0.5), m)
        }
    }

    mutating func triangle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ m: Mat) {
        func s(_ p: (Double, Double), _ q: (Double, Double), _ r: (Double, Double)) -> Double {
            (p.0 - r.0) * (q.1 - r.1) - (q.0 - r.0) * (p.1 - r.1)
        }
        for y in 0..<H {
            for x in 0..<W {
                let p = (Double(x) + 0.5, Double(y) + 0.5)
                let d1 = s(p, a, b), d2 = s(p, b, c), d3 = s(p, c, a)
                let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
                if !(neg && pos) { plot(x, y, m) }
            }
        }
    }

    /// Follows a curling path (angles in degrees, y down) and stamps circles along it.
    /// Returns the end point.
    @discardableResult
    mutating func path(from start: (Double, Double), angle: Double, curl: Double, segments: Int, step: Double,
                       radius: (Int) -> Double, mat: (Int) -> Mat) -> (Double, Double) {
        var p = start, a = angle
        for i in 0..<segments {
            let rad = a * .pi / 180
            let next = (p.0 + cos(rad) * step, p.1 + sin(rad) * step)
            let r = radius(i)
            line(p.0, p.1, next.0, next.1, r * 2, nil, mat(i))
            p = next
            a += curl
        }
        return p
    }

    mutating func paint(_ x: Double, _ y: Double, _ i: Ink) {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        if inside(xi, yi) { detail[yi * W + xi] = i }
    }

    /// Paints only where there is already a silhouette (keeps details from floating).
    mutating func paintOnBody(_ x: Double, _ y: Double, _ i: Ink) {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        if matAt(xi, yi) != .none { detail[yi * W + xi] = i }
    }

    /// Materials → inks: shading, outline, then details.
    mutating func resolve() {
        for y in 0..<H {
            for x in 0..<W {
                let m = matAt(x, y)
                let above = matAt(x, y - 1), below = matAt(x, y + 1)
                var out: Ink
                switch m {
                case .none:
                    let n = [matAt(x - 1, y), matAt(x + 1, y), above, below]
                    out = n.contains { $0 != .none } ? .outline : .clear
                case .body:
                    out = below == .none ? .shade : (above == .none ? .light : .base)
                case .far: out = .far
                case .dark: out = below == .none ? .darkShade : .dark
                case .cream: out = .cream
                case .pink: out = .pink
                }
                ink[y * W + x] = out
            }
        }
        for i in 0..<(W * H) { if let d = detail[i] { ink[i] = d } }
    }
}

// MARK: - Poses

enum Eyes { case open, closed }

struct Leg { var dx = 0.0; var lift = 0.0 }

struct Pose {
    var bodyY = 0.0          // + is down
    var stretch = 1.0        // body length factor (running)
    var breathe = 0.0        // extra body radius (idle / sleep)
    var crouch = 0.0         // 0..1, squashes before a jump
    var frontNear = Leg(), frontFar = Leg(), backNear = Leg(), backFar = Leg()
    var tail = 0.0           // tail swing, degrees
    var headDY = 0.0
    var earsBack = false
    var eyes = Eyes.open
    var lying = false
    var zs: [(Double, Double, Int)] = [] // sleep letters: x, y, size (2 or 3)
}

func idlePoses() -> [Pose] {
    (0..<4).map { f in
        var p = Pose()
        p.tail = sin(Double(f) / 4 * 2 * .pi) * 12
        p.breathe = (f == 1 || f == 2) ? 0.35 : 0
        p.eyes = f == 3 ? .closed : .open
        return p
    }
}

func walkPoses() -> [Pose] {
    (0..<6).map { f in
        let ph = Double(f) / 6 * 2 * .pi
        var p = Pose()
        func leg(_ off: Double) -> Leg { Leg(dx: sin(ph + off) * 2.0, lift: max(0, cos(ph + off)) * 1.4) }
        p.frontNear = leg(0); p.backFar = leg(0.2)
        p.frontFar = leg(.pi); p.backNear = leg(.pi + 0.2)
        p.bodyY = abs(sin(ph)) * 0.5 - 0.25
        p.tail = sin(ph) * 8
        return p
    }
}

func runPoses() -> [Pose] {
    (0..<6).map { f in
        let ph = Double(f) / 6 * 2 * .pi
        var p = Pose()
        // Lift only while a leg swings forward, so the collected phase still shows legs.
        func leg(_ off: Double) -> Leg {
            Leg(dx: sin(ph + off) * 3.0, lift: max(0, cos(ph + off)) * max(0, sin(ph + off) + 0.3) * 2.6)
        }
        p.frontNear = leg(0); p.frontFar = leg(0.5)
        p.backNear = leg(.pi); p.backFar = leg(.pi + 0.5)
        p.stretch = 1.0 + 0.08 * cos(ph)
        p.bodyY = -sin(ph) * 0.6
        p.headDY = 0.5
        p.earsBack = true
        p.tail = -14 + sin(ph) * 6
        return p
    }
}

func jumpPoses() -> [Pose] {
    var frames: [Pose] = []
    var p = Pose()
    // 0: crouch
    p.crouch = 1; p.tail = 10
    frames.append(p)
    // 1: launch — legs push back
    p = Pose(); p.bodyY = -1; p.stretch = 1.1; p.earsBack = true
    p.frontNear = Leg(dx: 2.5, lift: 2.5); p.frontFar = Leg(dx: 2, lift: 2)
    p.backNear = Leg(dx: -3, lift: 0.5); p.backFar = Leg(dx: -2.5, lift: 0.5)
    frames.append(p)
    // 2: airborne, tucked
    p = Pose(); p.bodyY = -2; p.earsBack = true; p.tail = -10
    p.frontNear = Leg(dx: 1.5, lift: 3.5); p.frontFar = Leg(dx: 1, lift: 3.5)
    p.backNear = Leg(dx: -1.5, lift: 3.5); p.backFar = Leg(dx: -1, lift: 3.5)
    frames.append(p)
    // 3: airborne, stretched
    p = Pose(); p.bodyY = -2; p.stretch = 1.12; p.earsBack = true; p.tail = -16
    p.frontNear = Leg(dx: 3.5, lift: 2.5); p.frontFar = Leg(dx: 3, lift: 2.5)
    p.backNear = Leg(dx: -3.5, lift: 2.5); p.backFar = Leg(dx: -3, lift: 2.5)
    frames.append(p)
    // 4: landing
    p = Pose(); p.bodyY = 0.5; p.headDY = 0.5
    p.frontNear = Leg(dx: 2, lift: 0); p.frontFar = Leg(dx: 1.5, lift: 0)
    p.backNear = Leg(dx: -1.5, lift: 1.5); p.backFar = Leg(dx: -1, lift: 1.5)
    frames.append(p)
    // 5: recover
    p = Pose(); p.crouch = 0.4; p.tail = 6
    frames.append(p)
    return frames
}

func sleepPoses() -> [Pose] {
    let letters: [[(Double, Double, Int)]] = [
        [(24, 14, 3)],
        [(25, 10, 3), (22, 15, 3)],
        [(26, 5, 4), (23, 11, 3)],
        [(27, 1, 4), (24, 7, 3)],
    ]
    return (0..<4).map { f in
        var p = Pose()
        p.lying = true
        p.eyes = .closed
        p.breathe = (f == 1 || f == 2) ? 0.4 : 0
        p.tail = 30
        p.zs = letters[f]
        return p
    }
}

func drawZ(_ c: inout Canvas, _ x: Double, _ y: Double, _ size: Int) {
    let n = size
    for i in 0..<n {
        c.paint(x + Double(i), y, .zzz)
        c.paint(x + Double(i), y + Double(n - 1), .zzz)
        c.paint(x + Double(n - 1 - i), y + Double(i), .zzz)
    }
}

// MARK: - Quadrupeds (cat, dog, fox, panda)

struct Quad {
    var body = (x: 14.5, y: 20.5, rx: 7.5, ry: 4.0)
    var head = (dx: 9.0, dy: -5.5, rx: 4.4, ry: 4.0)
    var legT = 2.2
    var frontHip = 4.8, backHip = -5.0, farOffset = 1.7
    var legMat = Mat.body
    var sock: (mat: Mat, length: Double)? = nil
    var tail: (inout Canvas, (Double, Double), Pose) -> Void = { _, _, _ in }
    var farEar: (inout Canvas, Double, Double, Pose) -> Void = { _, _, _, _ in }
    var nearEar: (inout Canvas, Double, Double, Pose) -> Void = { _, _, _, _ in }
    var face: (inout Canvas, Double, Double, Pose) -> Void = { _, _, _, _ in }   // materials on the head
    var bodyMarks: (inout Canvas, Double, Double, Pose) -> Void = { _, _, _, _ in }
    var details: (inout Canvas, Double, Double, Double, Double, Pose) -> Void = { _, _, _, _, _, _ in }

    func draw(_ p: Pose) -> Canvas {
        var c = Canvas()
        let rx = body.rx * p.stretch + p.breathe * 0.5
        var ry = body.ry + p.breathe
        var bx = body.x + (p.stretch - 1) * 4
        var by = body.y + p.bodyY + p.crouch * 2
        var hx = bx + head.dx * (0.85 + 0.15 * p.stretch)
        var hy = by + head.dy + p.headDY + p.crouch * 0.5
        if p.lying {
            ry *= 0.85
            by = ground + 1 - ry
            bx -= 0.5
            hx = bx + head.dx - 0.5
            hy = ground + 1 - head.ry * 0.95
        }

        // Far side first so the body covers it.
        farEar(&c, hx, hy, p)
        let hipY = by + ry * 0.3
        func leg(_ hip: Double, _ l: Leg, _ m: Mat) {
            let footY = ground - l.lift - (p.crouch > 0 ? 0 : 0)
            let fx = bx + hip + l.dx
            c.line(bx + hip, hipY, fx, footY, legT, nil, m)
            if let sock = sock {
                let t = sock.length / max(1, footY - hipY)
                c.line(fx + (bx + hip - fx) * t, footY - sock.length, fx, footY, legT, nil, m == .far ? .dark : sock.mat)
            }
        }
        if !p.lying {
            leg(frontHip + farOffset, p.frontFar, .far)
            leg(backHip + farOffset, p.backFar, .far)
        }
        tail(&c, (bx - rx + 1.2, by - ry * 0.35), p)
        c.ellipse(bx, by, rx, ry, .body)
        // Neck joins head and body.
        c.line(bx + rx * 0.55, by - ry * 0.3, hx - 1, hy + 1, 4.2, nil, .body)
        bodyMarks(&c, bx, by, p)
        if !p.lying {
            leg(frontHip, p.frontNear, legMat)
            leg(backHip, p.backNear, legMat)
        } else {
            // Tucked paws peeking out in front.
            c.ellipse(bx + rx - 0.5, ground - 0.2, 2.2, 1.2, legMat)
        }
        c.ellipse(hx, hy, head.rx, head.ry, .body)
        face(&c, hx, hy, p)
        nearEar(&c, hx, hy, p)

        details(&c, hx, hy, bx, by, p)
        if p.eyes == .closed {
            // Closed eyes are drawn by `details`; nothing extra.
        }
        for z in p.zs { drawZ(&c, z.0, z.1, z.2) }
        c.resolve()
        return c
    }
}

func closedEye(_ c: inout Canvas, _ x: Double, _ y: Double) {
    c.paintOnBody(x - 1, y + 1, .eye)
    c.paintOnBody(x, y + 1, .eye)
}

func openEye(_ c: inout Canvas, _ x: Double, _ y: Double) {
    c.paintOnBody(x, y, .eye)
    c.paintOnBody(x, y + 1, .eye)
}

let cat: Quad = {
    var q = Quad()
    q.tail = { c, base, p in
        c.path(from: base, angle: 200 - p.tail * 0.6, curl: 11 + p.tail * 0.3, segments: 10, step: 1.15,
               radius: { i in 1.0 - Double(i) * 0.03 }, mat: { _ in .body })
    }
    q.farEar = { c, hx, hy, p in
        let back = p.earsBack ? -1.2 : 0
        c.triangle((hx + 0.2, hy - 2.6), (hx + 2.0 + back, hy - 6.8), (hx + 3.6, hy - 2.2), .far)
    }
    q.nearEar = { c, hx, hy, p in
        let back = p.earsBack ? -1.4 : 0
        c.triangle((hx - 3.4, hy - 1.6), (hx - 2.0 + back, hy - 6.6), (hx + 0.4, hy - 2.8), .body)
    }
    q.details = { c, hx, hy, _, _, p in
        if p.eyes == .open { openEye(&c, hx + 1.8, hy - 0.8) } else { closedEye(&c, hx + 2.2, hy - 0.8) }
        c.paintOnBody(hx - 1.8, hy - 3.6, .pink)
        c.paintOnBody(hx + 4.0, hy + 0.6, .pink)
    }
    return q
}()

let dog: Quad = {
    var q = Quad()
    q.body = (14.5, 20.3, 8.0, 4.4)
    q.head = (9.2, -5.6, 4.2, 3.9)
    q.legT = 2.4
    q.tail = { c, base, p in
        c.path(from: (base.0 + 0.5, base.1), angle: 235 - p.tail * 1.5, curl: 6, segments: 4, step: 1.2,
               radius: { _ in 1.1 }, mat: { _ in .body })
    }
    q.face = { c, hx, hy, _ in
        c.ellipse(hx + 3.4, hy + 1.4, 2.7, 1.9, .body)
    }
    q.nearEar = { c, hx, hy, p in
        let swing = p.earsBack ? -1.5 : 0
        c.ellipse(hx - 1.7 + swing, hy + 0.2, 1.5, 3.0, .far)
    }
    q.bodyMarks = { c, bx, by, _ in _ = (c, bx, by) }
    q.details = { c, hx, hy, bx, by, p in
        if p.eyes == .open { openEye(&c, hx + 1.4, hy - 1.4) } else { closedEye(&c, hx + 1.8, hy - 1.4) }
        c.paintOnBody(hx + 5.6, hy + 0.6, .eye)
        c.paintOnBody(hx + 5.6, hy + 1.6, .eye)
        // Red collar where the neck meets the head.
        for dy in stride(from: -1.5, through: 2.5, by: 1.0) {
            c.paintOnBody(hx - 3.4, hy + dy, .collar)
            c.paintOnBody(hx - 4.2, hy + dy + 0.6, .collar)
        }
        _ = (bx, by)
    }
    return q
}()

let fox: Quad = {
    var q = Quad()
    q.body = (14.5, 20.6, 7.4, 3.7)
    q.head = (8.9, -5.2, 3.9, 3.6)
    q.legT = 1.9
    q.sock = (.dark, 2.4)
    q.tail = { c, base, p in
        c.path(from: base, angle: 188 - p.tail * 0.5, curl: -5 + p.tail * 0.2, segments: 8, step: 1.25,
               radius: { i in [1.2, 1.7, 2.2, 2.5, 2.6, 2.4, 2.0, 1.4][i] },
               mat: { i in i >= 6 ? .cream : .body })
    }
    q.farEar = { c, hx, hy, p in
        let back = p.earsBack ? -1.5 : 0
        c.triangle((hx + 0.3, hy - 2.4), (hx + 2.0 + back, hy - 8.0), (hx + 3.6, hy - 1.8), .far)
    }
    q.nearEar = { c, hx, hy, p in
        let back = p.earsBack ? -1.6 : 0
        c.triangle((hx - 3.2, hy - 1.2), (hx - 1.8 + back, hy - 7.8), (hx + 0.6, hy - 2.6), .body)
    }
    q.face = { c, hx, hy, _ in
        c.triangle((hx + 1.0, hy - 1.6), (hx + 6.8, hy + 1.8), (hx + 0.6, hy + 3.0), .body)
        c.ellipse(hx + 2.6, hy + 2.2, 2.2, 1.0, .cream)
    }
    q.bodyMarks = { c, bx, by, _ in
        c.ellipse(bx + 6.0, by + 0.8, 2.0, 2.3, .cream)
    }
    q.details = { c, hx, hy, _, _, p in
        if p.eyes == .open {
            c.paintOnBody(hx + 1.6, hy - 0.8, .eye)
            c.paintOnBody(hx + 2.6, hy - 0.8, .eye)
        } else { closedEye(&c, hx + 2.4, hy - 1.0) }
        c.paintOnBody(hx + 6.2, hy + 1.2, .eye)
        c.paintOnBody(hx - 1.6, hy - 4.6, .eye)
    }
    return q
}()

let panda: Quad = {
    var q = Quad()
    q.body = (14.5, 20.0, 8.4, 5.0)
    q.head = (9.0, -5.0, 4.8, 4.4)
    q.legT = 2.8
    q.legMat = .dark
    q.frontHip = 4.6
    q.backHip = -5.2
    q.tail = { c, base, _ in c.circle(base.0 - 0.2, base.1, 1.4, .cream) }
    q.farEar = { c, hx, hy, _ in c.circle(hx + 2.3, hy - 4.0, 1.7, .dark) }
    q.nearEar = { c, hx, hy, _ in c.circle(hx - 2.4, hy - 3.6, 1.8, .dark) }
    q.face = { c, hx, hy, _ in
        c.ellipse(hx + 3.0, hy + 1.6, 2.2, 1.6, .body)
        c.ellipse(hx + 1.6, hy - 0.2, 1.6, 1.9, .dark)
    }
    q.bodyMarks = { c, bx, by, p in
        if !p.lying { c.ellipse(bx + 4.8, by - 0.5, 2.6, 4.6, .dark) }
    }
    q.details = { c, hx, hy, _, _, p in
        if p.eyes == .open {
            c.paintOnBody(hx + 1.8, hy - 0.6, .glint)
        } else {
            c.paintOnBody(hx + 1.2, hy + 0.4, .eye)
            c.paintOnBody(hx + 2.2, hy + 0.4, .eye)
        }
        c.paintOnBody(hx + 4.8, hy + 0.6, .eye)
        c.paintOnBody(hx + 5.0, hy + 1.4, .eye)
    }
    return q
}()

// MARK: - Rabbit

func rabbitHopPoses(height: Double, reach: Double, frames: Int) -> [Pose] {
    (0..<frames).map { f in
        let t = Double(f) / Double(frames)
        let air = max(0, sin(t * 2 * .pi))
        var p = Pose()
        p.bodyY = -air * height
        let swing = sin(t * 2 * .pi + .pi / 2)
        p.frontNear = Leg(dx: swing * reach, lift: air * height * 0.6)
        p.backNear = Leg(dx: -swing * reach, lift: air * height * 0.4)
        p.earsBack = air > 0.5
        p.tail = swing * 10
        return p
    }
}

func drawRabbit(_ p: Pose) -> Canvas {
    var c = Canvas()
    var bx = 13.5, by = 21.0 + p.bodyY + p.crouch * 1.5
    let rx = 6.4 * p.stretch + p.breathe * 0.4, ry = 4.9 + p.breathe
    var hx = bx + 7.2, hy = by - 6.0 + p.headDY
    if p.lying {
        by = ground + 1 - ry * 0.9
        bx -= 0.5
        hx = bx + 7.0
        hy = ground + 1 - 3.6
    }
    // Ears (far one first).
    let lean = p.earsBack ? -3.0 : (p.lying ? -4.5 : -0.6)
    let earLen = p.lying ? 8.0 : 9.0
    c.line(hx + 0.9, hy - 2.6, hx + 1.0 + lean, hy - 2.6 - earLen * (p.lying ? 0.7 : 1), 2.3, 1.8, .far)
    // Tail puff.
    c.circle(bx - rx + 0.6, by - 1.4, 1.9, .cream)
    if !p.lying {
        // Front leg (far side hidden behind the body; rabbits read better with one).
        c.line(bx + 3.8, by + 1.5, bx + 4.4 + p.frontNear.dx, ground - p.frontNear.lift, 2.0, nil, .body)
    }
    c.ellipse(bx, by, rx, ry, .body)
    // Big haunch + long hind foot.
    let footY = ground - p.backNear.lift
    c.ellipse(bx - 2.6, by + 1.4, 3.3, 3.2, .body)
    if !p.lying {
        c.line(bx - 5.0 + p.backNear.dx, footY, bx - 0.5 + p.backNear.dx, footY, 2.0, nil, .body)
        c.line(bx - 2.6, by + 2.5, bx - 2.0 + p.backNear.dx, footY, 2.2, nil, .body)
    } else {
        c.line(bx - 5.0, ground - 0.2, bx - 0.5, ground - 0.2, 1.8, nil, .body)
        c.ellipse(bx + rx - 0.6, ground - 0.2, 2.0, 1.2, .body)
    }
    c.line(bx + rx * 0.5, by - ry * 0.4, hx - 1, hy + 1, 3.6, nil, .body)
    c.ellipse(hx, hy, 3.9, 3.5, .body)
    c.line(hx - 0.6, hy - 2.6, hx - 0.4 + lean, hy - 2.6 - earLen * (p.lying ? 0.7 : 1), 2.4, 2.0, .body)
    // Inner ear.
    let earRise = p.lying ? 0.8 : 1.2
    for i in 1...(p.lying ? 4 : 5) {
        c.paintOnBody(hx - 0.5 + lean * Double(i) / 7, hy - 3.2 - Double(i) * earRise, .pink)
    }
    if p.eyes == .open { openEye(&c, hx + 1.6, hy - 1.0) } else { closedEye(&c, hx + 2.0, hy - 1.0) }
    c.paintOnBody(hx + 3.6, hy + 0.6, .pink)
    for z in p.zs { drawZ(&c, z.0, z.1, z.2) }
    c.resolve()
    return c
}

// MARK: - Dinosaur (biped)

func drawDino(_ p: Pose) -> Canvas {
    var c = Canvas()
    var bx = 13.5 + (p.stretch - 1) * 3, by = 18.8 + p.bodyY + p.crouch * 2
    let rx = 6.2 * p.stretch + p.breathe * 0.4, ry = 5.0 + p.breathe
    var hx = bx + 9.0, hy = by - 7.6 + p.headDY + p.crouch * 0.5 + (p.earsBack ? 1.0 : 0)
    if p.lying {
        by = ground + 1 - ry * 0.85
        hx = bx + 9.5
        hy = ground + 1 - 3.6
    }
    let legs: [(Double, Leg, Mat)] = [(1.6, p.frontFar, .far), (0, p.frontNear, .body)]
    func leg(_ off: Double, _ l: Leg, _ m: Mat) {
        let hip = (bx + 0.5 + off, by + 2.0)
        let foot = (bx + 0.8 + off + l.dx * 1.2, ground - l.lift)
        c.ellipse(hip.0, hip.1, 2.6, 3.0, m)
        c.line(hip.0, hip.1 + 1, foot.0, foot.1, 2.6, 2.2, m)
        c.line(foot.0 - 0.5, foot.1, foot.0 + 2.4, foot.1, 1.6, nil, m)
    }
    // Spikes along the back.
    for (i, sx) in [-3.5, -0.5, 2.5].enumerated() {
        let top = by - ry * (i == 1 ? 1.0 : 0.92)
        c.triangle((bx + sx - 1.4, top + 1.2), (bx + sx, top - 1.8), (bx + sx + 1.4, top + 1.2), .far)
    }
    if !p.lying { leg(legs[0].0, legs[0].1, legs[0].2) }
    // Tail tapers to the left; sways with the pose.
    c.path(from: (bx - rx + 2, by - 0.5), angle: 165 + p.tail * 0.4, curl: (p.lying ? -6 : 3) - p.tail * 0.15,
           segments: 7, step: 1.35, radius: { i in 2.6 - Double(i) * 0.3 }, mat: { _ in .body })
    c.ellipse(bx, by, rx, ry, .body)
    c.line(bx + rx * 0.5, by - ry * 0.5, hx - 2.4, hy + 1.4, 4.6, 3.8, .body)
    // Head and jaw.
    c.ellipse(hx, hy, 4.9, 3.2, .body)
    c.ellipse(hx + 0.6, hy + 2.4, 4.0, 1.5, .body)
    // Arms.
    if !p.lying {
        let wave = p.earsBack ? 1.0 : 0
        c.line(bx + rx - 1.2, by + 0.4, bx + rx + 1.0, by + 2.0 - wave, 1.4, nil, .body)
        leg(legs[1].0, legs[1].1, legs[1].2)
    } else {
        c.ellipse(bx + 2, ground - 0.4, 3.0, 1.4, .body)
    }
    // Belly stripe.
    c.ellipse(bx + 2.4, by + 1.4, 2.6, 2.6, .cream)
    if p.eyes == .open {
        c.paintOnBody(hx + 0.8, hy - 1.2, .eye)
        c.paintOnBody(hx + 0.8, hy - 0.2, .eye)
        c.paintOnBody(hx + 0.2, hy - 2.0, .eye) // brow
    } else { closedEye(&c, hx + 1.4, hy - 1.4) }
    c.paintOnBody(hx + 4.0, hy - 0.8, .eye) // nostril
    for i in 0..<3 { c.paintOnBody(hx + 1.0 + Double(i) * 1.4, hy + 1.2, .tooth) }
    for z in p.zs { drawZ(&c, z.0, z.1, z.2) }
    c.resolve()
    return c
}

// MARK: - Species table

struct Species {
    let id: String
    let name: String
    let baseColor: String
    let draw: (Pose) -> Canvas
    let poses: [String: [Pose]]
}

let standard: [String: [Pose]] = [
    "idle": idlePoses(), "walk": walkPoses(), "run": runPoses(), "jump": jumpPoses(), "sleep": sleepPoses(),
]

func bipedRunPoses(reach: Double, lift: Double) -> [Pose] {
    (0..<6).map { f in
        let ph = Double(f) / 6 * 2 * .pi
        var p = Pose()
        p.frontNear = Leg(dx: sin(ph) * reach, lift: max(0, cos(ph)) * lift)
        p.frontFar = Leg(dx: sin(ph + .pi) * reach, lift: max(0, cos(ph + .pi)) * lift)
        p.bodyY = -abs(sin(ph)) * (lift * 0.4)
        p.tail = sin(ph) * 10
        p.earsBack = reach > 2.5
        return p
    }
}

let species: [Species] = [
    Species(id: "cat", name: "Cat", baseColor: "#F2A65A", draw: cat.draw, poses: standard),
    Species(id: "dog", name: "Dog", baseColor: "#C98B5B", draw: dog.draw, poses: standard),
    Species(id: "fox", name: "Fox", baseColor: "#F07F2E", draw: fox.draw, poses: standard),
    Species(id: "rabbit", name: "Rabbit", baseColor: "#CFC6BE", draw: drawRabbit, poses: [
        "idle": idlePoses(), "walk": rabbitHopPoses(height: 2.0, reach: 1.5, frames: 6),
        "run": rabbitHopPoses(height: 3.6, reach: 2.8, frames: 6), "jump": jumpPoses(), "sleep": sleepPoses(),
    ]),
    Species(id: "dinosaur", name: "Dinosaur", baseColor: "#6CC56C", draw: drawDino, poses: [
        "idle": idlePoses(), "walk": bipedRunPoses(reach: 2.0, lift: 1.4),
        "run": bipedRunPoses(reach: 3.4, lift: 2.6), "jump": jumpPoses(), "sleep": sleepPoses(),
    ]),
    Species(id: "panda", name: "Panda", baseColor: "#F4F4F2", draw: panda.draw, poses: standard),
]

let animOrder: [(name: String, fps: Int, loop: Bool)] = [
    ("idle", 4, true), ("walk", 8, true), ("run", 12, true), ("jump", 10, false), ("sleep", 2, true),
]

// MARK: - Output

func makeImage(width: Int, height: Int, gray: Bool, pixels: [UInt8]) -> CGImage {
    let cs = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
    let bpp = gray ? 1 : 4
    let info: CGBitmapInfo = gray ? [] : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * bpp,
                   bytesPerRow: width * bpp, space: cs, bitmapInfo: info, provider: provider,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

func strip(_ frames: [Canvas]) -> (CGImage, CGImage) {
    let w = W * frames.count
    var rgba = [UInt8](repeating: 0, count: w * H * 4)
    var mask = [UInt8](repeating: 0, count: w * H)
    for (f, c) in frames.enumerated() {
        for y in 0..<H {
            for x in 0..<W {
                let ink = c.ink[y * W + x]
                let (r, g, b, a) = ink.rgba
                let o = (y * w + f * W + x)
                rgba[o * 4] = r; rgba[o * 4 + 1] = g; rgba[o * 4 + 2] = b; rgba[o * 4 + 3] = a
                mask[o] = ink.tinted ? 255 : 0
            }
        }
    }
    return (makeImage(width: w, height: H, gray: false, pixels: rgba),
            makeImage(width: w, height: H, gray: true, pixels: mask))
}

var args = Array(CommandLine.arguments.dropFirst())
var previewURL: URL? = nil
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    previewURL = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i...(i + 1))
}
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outRoot = args.first.map { URL(fileURLWithPath: $0) }
    ?? scriptDir.appendingPathComponent("../macos/mypet/Assets/Pets").standardizedFileURL

let fm = FileManager.default
var previewRows: [(Species, [String: [Canvas]])] = []

for s in species {
    let dir = outRoot.appendingPathComponent(s.id)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var rendered: [String: [Canvas]] = [:]
    var anims: [String: Any] = [:]
    for a in animOrder {
        let frames = s.poses[a.name]!.map(s.draw)
        rendered[a.name] = frames
        let (img, mask) = strip(frames)
        writePNG(img, to: dir.appendingPathComponent("\(a.name).png"))
        writePNG(mask, to: dir.appendingPathComponent("\(a.name)_mask.png"))
        anims[a.name] = ["frames": frames.count, "fps": a.fps, "loop": a.loop]
    }
    let manifest: [String: Any] = [
        "id": s.id, "displayName": s.name, "frameSize": [W, H], "baseColor": s.baseColor,
        "animations": anims, "menuBarAnimation": "run", "author": "mypet", "license": "MIT",
    ]
    let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: dir.appendingPathComponent("manifest.json"))
    previewRows.append((s, rendered))
    print("✓ \(s.id)")
}

// Contact sheet: every frame of every pet at 4×, tinted with each pet's base colour.
if let previewURL {
    let scale = 4, pad = 4
    let maxFrames = animOrder.reduce(0) { $0 + (previewRows[0].1[$1.name]?.count ?? 0) } + animOrder.count - 1
    let cw = (maxFrames * (W + pad)) * scale, ch = previewRows.count * (H + pad) * scale
    let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
    ctx.interpolationQuality = .none
    for (row, (s, rendered)) in previewRows.enumerated() {
        let hex = Int(s.baseColor.dropFirst(), radix: 16)!
        let tint = (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
        var col = 0
        for a in animOrder {
            for c in rendered[a.name]! {
                var px = [UInt8](repeating: 0, count: W * H * 4)
                for i in 0..<(W * H) {
                    var (r, g, b, al) = c.ink[i].rgba
                    if c.ink[i].tinted {
                        r = UInt8(Double(r) * tint.0); g = UInt8(Double(g) * tint.1); b = UInt8(Double(b) * tint.2)
                    }
                    px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = al
                }
                let img = makeImage(width: W, height: H, gray: false, pixels: px)
                let x = col * (W + pad) * scale
                let y = ch - (row + 1) * (H + pad) * scale
                ctx.draw(img, in: CGRect(x: x, y: y, width: W * scale, height: H * scale))
                col += 1
            }
            col += 1
        }
    }
    writePNG(ctx.makeImage()!, to: previewURL)
    print("preview → \(previewURL.path)")
}
