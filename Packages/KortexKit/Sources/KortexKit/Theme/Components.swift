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
            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
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
