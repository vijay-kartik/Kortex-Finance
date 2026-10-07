import SwiftUI

extension View {
    /// A fixed-width details panel on the right edge (Figma: the Mac inspectors).
    ///
    /// Not SwiftUI's `.inspector`: inside a NavigationSplitView detail that also has toolbar items,
    /// it sends AppKit into an endless constraint-update loop and the app is terminated
    /// ("more Update Constraints in Window passes than there are views in the window").
    func sidePanel<Panel: View>(isPresented: Bool, width: CGFloat = 340, @ViewBuilder panel: () -> Panel) -> some View {
        HStack(spacing: 0) {
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
            if isPresented {
                Rectangle().fill(Color.kEdge).frame(width: 1)
                panel()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented)
    }
}
