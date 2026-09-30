import SwiftUI

/// Source of `Resources/AppIcon.icns` and the DMG background; `make-artwork.sh` renders them.
/// Drawn from shapes because SF Symbols may not be used in app icons.
struct AppIconArt: View {
    static let size: CGFloat = 1024

    private let top = Color(red: 0.31, green: 0.27, blue: 0.90)
    private let bottom = Color(red: 0.58, green: 0.20, blue: 0.92)
    private let ink = Color(red: 0.22, green: 0.19, blue: 0.64)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

            socket
                .offset(y: 30)

            Circle()
                .fill(Color(red: 0.20, green: 0.83, blue: 0.60))
                .overlay(Circle().strokeBorder(.white, lineWidth: 16))
                .frame(width: 150, height: 150)
                .offset(x: 250, y: -215)
        }
        .frame(width: Self.size, height: Self.size)
    }

    private var socket: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(.white)
                .frame(width: 500, height: 330)
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.white)
                .frame(width: 240, height: 440)
            HStack(spacing: 30) {
                ForEach(0..<6, id: \.self) { _ in
                    Capsule().fill(ink).frame(width: 30, height: 120)
                }
            }
            .padding(.top, 58)
        }
        .frame(height: 440, alignment: .top)
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }
}

/// Finder window background for the DMG. Icon positions live in `packaging/dmg/settings.py`.
struct DMGBackgroundArt: View {
    static let size = CGSize(width: 660, height: 400)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.985), Color(red: 0.93, green: 0.92, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
            Arrow()
                .stroke(Color(red: 0.45, green: 0.40, blue: 0.85).opacity(0.5),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 28)
                .offset(y: -15)
            VStack {
                Spacer()
                Text("Drag WhyPort into Applications")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.bottom, 52)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }

    private struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.move(to: CGPoint(x: rect.maxX - rect.height * 0.6, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.height * 0.6, y: rect.maxY))
            return path
        }
    }
}
