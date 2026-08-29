import SwiftUI

extension Color {
  static let ozBackground = Color("Background")
  static let ozSurface = Color("Surface")
  static let ozElevated = Color("Elevated")
  static let ozLine = Color("Line")
  static let ozInk = Color("Ink")
  static let ozMuted = Color("Muted")
  static let ozAccent = Color("AccentColor")
  static let ozAccentInk = Color("AccentInk")
  static let ozDanger = Color("Danger")
  static let ozWarning = Color("Warning")
  static let ozOkay = Color("Okay")
}

struct OzymandiasCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(Color.ozSurface, in: .rect(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color.ozLine, lineWidth: 1)
      }
  }
}

extension View {
  func ozyCard() -> some View { modifier(OzymandiasCardModifier()) }
}
