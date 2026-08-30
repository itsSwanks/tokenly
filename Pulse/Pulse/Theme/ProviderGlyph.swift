import SwiftUI
import PulseCore

/// Eight rounded rays — Pulse's own mark for Claude, not Anthropic's logo.
struct ClaudeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 26, c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + .pi / 8
            p.move(to: CGPoint(x: c.x + cos(a) * 4.0 * s, y: c.y + sin(a) * 4.0 * s))
            p.addLine(to: CGPoint(x: c.x + cos(a) * 11.8 * s, y: c.y + sin(a) * 11.8 * s))
        }
        return p.strokedPath(StrokeStyle(lineWidth: 2.7 * s, lineCap: .round))
    }
}

/// Six-petal knot — Pulse's own mark for Codex.
struct CodexGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 26, c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<6 {
            let ellipse = CGRect(x: c.x - 3.1 * s, y: c.y - 6.2 * s - 6.8 * s, width: 6.2 * s, height: 13.6 * s)
            let rotate = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: Double(i) * .pi / 3)
                .translatedBy(x: -c.x, y: -c.y)
            p.addPath(Path(ellipseIn: ellipse), transform: rotate)
        }
        return p.strokedPath(StrokeStyle(lineWidth: 1.9 * s))
    }
}

/// Four-point sparkle — Pulse's own mark for Gemini.
struct GeminiGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 26, c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 11.5 * s))
        p.addQuadCurve(to: CGPoint(x: c.x + 11.5 * s, y: c.y), control: CGPoint(x: c.x + 1.9 * s, y: c.y - 1.9 * s))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 11.5 * s), control: CGPoint(x: c.x + 1.9 * s, y: c.y + 1.9 * s))
        p.addQuadCurve(to: CGPoint(x: c.x - 11.5 * s, y: c.y), control: CGPoint(x: c.x - 1.9 * s, y: c.y + 1.9 * s))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 11.5 * s), control: CGPoint(x: c.x - 1.9 * s, y: c.y - 1.9 * s))
        p.closeSubpath()
        return p
    }
}

extension ProviderID {
    @ViewBuilder
    func glyph(size: CGFloat, color: Color = .white) -> some View {
        switch self {
        case .claude: ClaudeGlyph().fill(color).frame(width: size, height: size)
        case .codex: CodexGlyph().fill(color).frame(width: size, height: size)
        case .gemini: GeminiGlyph().fill(color).frame(width: size, height: size)
        }
    }
}
