import KortexFinance
import SwiftUI

/// The frame every Kortex sheet shares: a title, a native grouped form, the reason a save was
/// refused, and Cancel (esc) / primary (⏎) buttons.
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String?
    var primary = "Save"
    var destructive = false
    var error: String?
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.grotesk(20, .medium)).foregroundStyle(Color.kInk)
                if let subtitle { Text(subtitle).font(.grotesk(12)).foregroundStyle(Color.kMuted) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.grotesk(12))
                    .foregroundStyle(Color.kAlarm)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(primary, role: destructive ? .destructive : nil, action: onPrimary)
                    .keyboardShortcut(.defaultAction)
                    .tint(destructive ? .kAlarm : .kSynapse)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 560)
        .background(Color.kSheet)
    }
}

/// An amount field: "₹" then the number, in the Figma's big synapse type.
struct AmountField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Text("₹").foregroundStyle(Color.kMuted)
                TextField(label, text: $text, prompt: Text("0.00"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.mono(18))
                    .foregroundStyle(Color.kSynapse)
            }
            .frame(maxWidth: 220)
        }
    }
}

/// Picks one of your accounts and cards, as "HDFC Checking ••4471".
struct AccountPicker: View {
    let label: String
    @Binding var selection: String
    let accounts: [Account]

    var body: some View {
        Picker(label, selection: $selection) {
            if !accounts.contains(where: { $0.uid == selection }) { Text("Choose…").tag("") }
            ForEach(accounts) { a in
                Text(a.last4.map { "\(a.name) ••\($0)" } ?? a.name).tag(a.uid)
            }
        }
    }
}

/// Category chips, as on the Add expense sheet: tap one; the suggested one is marked.
struct CategoryChips: View {
    @Binding var selection: String?
    let categories: [SpendCategory]
    var suggested: String?

    var body: some View {
        FlowLayout(spacing: 6) {
            chip(nil, name: "Uncategorised", color: .kMuted)
            ForEach(categories) { c in chip(c.uid, name: c.name, color: Color.token(c.colorToken)) }
        }
    }

    private func chip(_ uid: String?, name: String, color: Color) -> some View {
        let selected = selection == uid
        return Button { selection = uid } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.grotesk(12)).foregroundStyle(selected ? Color.kSynapse : Color.kInk)
                if uid != nil && uid == suggested && !selected {
                    Text("suggested").font(.grotesk(10)).foregroundStyle(Color.kMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.kSynapseDim : Color.kPanel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.kSynapse : Color.kEdge))
        }
        .buttonStyle(.plain)
    }
}

/// Lays chips out in rows, wrapping to the width it's given.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
