import SwiftUI

/// A button in the floating action bar at the bottom of the sidebar
struct FloatingBarButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary.opacity(0.7))
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered || isActive ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Audio level visualization bar for recording
struct AudioLevelBar: View {
    let level: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * min(1, level * 3))
            }
        }
    }
}
