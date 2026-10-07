import SwiftUI

/// The whole window takes a dropped receipt (Figma: Mac · Drop a receipt — drag over), and a photo
/// from Continuity Camera (File › Import from iPhone).
struct ReceiptDropTarget: ViewModifier {
    let model: AppModel
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: ReceiptInput.types, isTargeted: $targeted) { providers in
                take(providers)
                return true
            }
            .importsItemProviders(ReceiptInput.types) { providers in
                take(providers)
                return true
            }
            .overlay {
                if targeted {
                    ZStack {
                        Color.kVoid.opacity(0.72)
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.kSynapse, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                            .background(Color.kSynapse.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                            .padding(16)
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.kSynapse)
                                .frame(width: 56, height: 56)
                                .background(Color.kSynapseDim, in: RoundedRectangle(cornerRadius: 16))
                            Text("Drop to read receipt").font(.grotesk(22, .medium)).foregroundStyle(Color.kInk)
                            Text("A photo or PDF · one receipt at a time").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                            Label("Read on this Mac. The image never leaves it.", systemImage: "lock").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        }
                        .padding(.horizontal, 36).padding(.vertical, 28)
                        .background(Color.kSheet, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.kSynapse.opacity(0.5)))
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private func take(_ providers: [NSItemProvider]) {
        guard model.sheet == nil else { return }
        Task { @MainActor in
            if let url = await ReceiptInput.load(providers) { model.sheet = .receipt(url) }
        }
    }
}
