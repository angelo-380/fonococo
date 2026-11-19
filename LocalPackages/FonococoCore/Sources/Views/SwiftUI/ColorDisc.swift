import SwiftUI
import UIKit

/// Hue ring and saturation/brightness disc for the drawing tools.
public struct ColorDisc: View {
    @Binding private var color: Color
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 0.0

    private let size: CGFloat = 280
    private let ringRadius: CGFloat = 130
    private let discRadius: CGFloat = 100

    public init(color: Binding<Color>) { _color = color }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(colors: (0...24).map {
                        Color(hue: Double($0) / 24, saturation: 1, brightness: 1)
                    }, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    lineWidth: 24
                )
                .frame(width: ringRadius * 2, height: ringRadius * 2)

            Circle()
                .fill(Color(hue: hue, saturation: 1, brightness: 1))
                .overlay {
                    Circle().fill(LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing))
                }
                .overlay {
                    Circle().fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                }
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                .frame(width: discRadius * 2, height: discRadius * 2)

            Circle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 3)
                .offset(hueOffset)

            Circle().fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 3)
                .offset(discOffset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { select(at: $0.location) })
        .onAppear(perform: readCurrentColor)
        .accessibilityLabel("Rueda de color")
        .accessibilityValue("Tono \(Int(hue * 360)) grados, saturación \(Int(saturation * 100)) por ciento, brillo \(Int(brightness * 100)) por ciento")
    }

    private var hueOffset: CGSize {
        let angle = hue * 2 * Double.pi - Double.pi / 2
        return CGSize(width: ringRadius * cos(angle), height: ringRadius * sin(angle))
    }

    private var discOffset: CGSize {
        let x = CGFloat(saturation * 2 - 1) * discRadius
        let y = CGFloat(1 - brightness * 2) * discRadius
        let distance = max(discRadius, hypot(x, y))
        return CGSize(width: x * discRadius / distance, height: y * discRadius / distance)
    }

    private func select(at location: CGPoint) {
        let dx = location.x - size / 2
        let dy = location.y - size / 2
        if hypot(dx, dy) > discRadius + 8 {
            let angle = atan2(Double(dy), Double(dx)) + Double.pi / 2
            hue = (angle / (2 * Double.pi) + 1).truncatingRemainder(dividingBy: 1)
        } else {
            saturation = min(1, max(0, Double((dx + discRadius) / (2 * discRadius))))
            brightness = min(1, max(0, Double((discRadius - dy) / (2 * discRadius))))
        }
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func readCurrentColor() {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            hue = Double(h); saturation = Double(s); brightness = Double(b)
        }
    }
}
