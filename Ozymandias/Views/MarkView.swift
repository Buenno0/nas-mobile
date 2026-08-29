import SwiftUI

struct MarkView: View {
  @Environment(\.colorScheme) private var colorScheme
  var size: CGFloat = 48

  var body: some View {
    Canvas { context, canvasSize in
      let sx = canvasSize.width / 96
      let sy = canvasSize.height / 96
      context.scaleBy(x: sx, y: sy)

      var body = Path()
      body.move(to: CGPoint(x: 18, y: 22))
      body.addCurve(
        to: CGPoint(x: 48, y: 9), control1: CGPoint(x: 18, y: 14), control2: CGPoint(x: 27, y: 9))
      body.addCurve(
        to: CGPoint(x: 78, y: 22), control1: CGPoint(x: 69, y: 9), control2: CGPoint(x: 78, y: 14))
      body.addLine(to: CGPoint(x: 78, y: 52))
      body.addCurve(
        to: CGPoint(x: 48, y: 87), control1: CGPoint(x: 78, y: 68), control2: CGPoint(x: 66, y: 80))
      body.addCurve(
        to: CGPoint(x: 18, y: 52), control1: CGPoint(x: 30, y: 80), control2: CGPoint(x: 18, y: 68))
      body.closeSubpath()
      context.fill(body, with: .color(bodyColor))

      var headdress = Path()
      headdress.move(to: CGPoint(x: 24, y: 24))
      headdress.addCurve(
        to: CGPoint(x: 48, y: 14), control1: CGPoint(x: 24, y: 18), control2: CGPoint(x: 32, y: 14))
      headdress.addCurve(
        to: CGPoint(x: 72, y: 24), control1: CGPoint(x: 64, y: 14), control2: CGPoint(x: 72, y: 18))
      headdress.addLine(to: CGPoint(x: 72, y: 34))
      headdress.addLine(to: CGPoint(x: 24, y: 34))
      headdress.closeSubpath()
      context.opacity = colorScheme == .dark ? 0.38 : 1
      context.fill(headdress, with: .color(headdressColor))
      context.fill(Path(CGRect(x: 24, y: 36, width: 48, height: 4)), with: .color(headdressColor))

      context.opacity = 1
      context.fill(
        Path(ellipseIn: CGRect(x: 29, y: 45, width: 16, height: 16)), with: .color(cutoutColor))
      context.fill(
        Path(ellipseIn: CGRect(x: 51, y: 45, width: 16, height: 16)), with: .color(cutoutColor))
      var play = Path()
      play.move(to: CGPoint(x: 41, y: 66))
      play.addLine(to: CGPoint(x: 41, y: 78))
      play.addLine(to: CGPoint(x: 55, y: 72))
      play.closeSubpath()
      context.fill(play, with: .color(cutoutColor))
    }
    .frame(width: size, height: size)
    .accessibilityLabel("Ozymandias")
  }

  private var bodyColor: Color { colorScheme == .dark ? .ozAccent : .ozInk }
  private var headdressColor: Color {
    colorScheme == .dark ? .ozAccentInk : Color(red: 0.788, green: 0.561, blue: 0.235)
  }
  private var cutoutColor: Color { colorScheme == .dark ? .ozAccentInk : .ozBackground }
}
