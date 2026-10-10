import KortexFinance
import SwiftUI

/// The Figma "Card": Panel fill, Edge hairline, radius 16.
struct KCard<Content: View>: View {
    var padding: CGFloat = 20
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .panelSurface()
    }
}

extension View {
    /// The Figma "Card" surface: Panel fill, Edge hairline, radius 16. `clipped` for edge-to-edge
    /// tables and lists, so their rows don't paint over the rounded corners.
    @ViewBuilder
    func panelSurface(clipped: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        if clipped {
            background(Color.kPanel, in: shape).clipShape(shape).overlay(shape.strokeBorder(Color.kEdge))
        } else {
            background(Color.kPanel, in: shape).overlay(shape.strokeBorder(Color.kEdge))
        }
    }
}

/// A card's title row: "Cash flow" on the left, anything on the right.
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.grotesk(16, .medium)).foregroundStyle(Color.kInk)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// An edge-to-edge panel's title row: "Entries" on the left, a count or filter on the right,
/// and a hairline under it.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.grotesk(15, .medium)).foregroundStyle(Color.kInk)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Hairline()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// "See all ›" style links in a card header.
struct CardLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title).font(.grotesk(13, .medium))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.kSynapse)
        }
        .buttonStyle(.plain)
    }
}

/// A hairline between rows.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.kEdge).frame(height: 1)
    }
}

/// The two-part Synapse bar: a solid capsule for `first`, a half-strength one for `rest`
/// (faint when `rest` is 0).
struct SplitBar: View {
    let first: Int64
    let rest: Int64
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                if first > 0 { Capsule().fill(Color.kSynapse).frame(width: Self.firstWidth(first: first, rest: rest, in: geo.size.width)) }
                Capsule().fill(Color.kSynapse.opacity(rest > 0 ? 0.5 : 0.15))
            }
        }
        .frame(height: height)
    }

    /// `first`'s share of `width`, less half the 3pt gap, and at least 6pt; 0 when there's no `first`.
    static func firstWidth(first: Int64, rest: Int64, in width: CGFloat) -> CGFloat {
        guard first > 0 else { return 0 }
        return max(6, width * CGFloat(first) / CGFloat(max(first + rest, 1)) - 1.5)
    }
}

/// A legend row under a bar: dot, muted label, amount in whole units. `spread` pushes the amount
/// to the trailing edge.
struct LegendRow: View {
    let color: Color
    let label: String
    let minor: Int64
    var spread = false

    init(_ color: Color, _ label: String, _ minor: Int64, spread: Bool = false) {
        self.color = color
        self.label = label
        self.minor = minor
        self.spread = spread
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.grotesk(13)).foregroundStyle(Color.kMuted)
            if spread { Spacer() }
            Text(Money.format(minor, wholeUnits: true)).font(.mono(13)).foregroundStyle(Color.kInk)
        }
    }
}

/// Category shares as one stacked bar, each segment in its category's colour and at least 4pt wide.
struct ShareBar: View {
    let shares: [CategoryShare]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let gaps = CGFloat(shares.count - 1) * 3
            HStack(spacing: 3) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.category(share.category))
                        .frame(width: max(4, (geo.size.width - gaps) * CGFloat(share.percent) / 100))
                }
            }
        }
        .frame(height: height)
    }
}

extension Color {
    /// A category's colour; Muted for no category.
    static func category(_ category: SpendCategory?) -> Color {
        category.map { Color.token($0.colorToken) } ?? .kMuted
    }
}

enum Format {
    /// "September".
    static func monthName(_ month: YearMonth) -> String {
        month.date.formatted(.dateTime.month(.wide))
    }

    /// "SEP".
    static func monthShort(_ month: YearMonth) -> String {
        month.date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    /// "Sat, 3 Oct".
    static func dueDay(_ day: LocalDay) -> String {
        day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Tuesday, 29 September".
    static func longDay(_ day: LocalDay) -> String {
        day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func points(_ n: Int) -> String { n == 1 ? "1 point" : "\(n) points" }
}
