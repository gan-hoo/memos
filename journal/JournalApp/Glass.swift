import SwiftUI

// iOS 26 液态玻璃效果；旧系统 / 旧 Xcode 回退到毛玻璃
#if compiler(>=6.2)
extension View {
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.circle)
        }
    }
}
#else
extension View {
    func glassCapsule() -> some View {
        background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
    }

    func glassCircle() -> some View {
        background(.regularMaterial, in: Circle())
    }

    func prominentGlassButton() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.circle)
    }
}
#endif
