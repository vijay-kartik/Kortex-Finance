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

/// The Figma "Button": radius 8, Space Grotesk medium. Primary is Synapse with a Void label, secondary
/// Panel with an Edge hairline and an Ink label, destructive Alarm with a Void label. `hint` is the
/// shortcut drawn after the label ("⏎", "esc"); it doesn't bind the key, so keep `.keyboardShortcut`.
/// Use it for actions in sheets and screens; toolbar items, header controls and menus stay native.
struct KortexButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive }

    enum Size {
        /// Sheet footers and screen actions: 32pt, 13pt label.
        case regular
        /// Row actions shown on hover: 26pt, 12pt label.
        case small
        /// The one call to action on an empty window (sign-in): 38pt, 14pt label.
        case large

        var height: CGFloat {
            switch self {
            case .regular: 32
            case .small: 26
            case .large: 38
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .regular: 13
            case .small: 12
            case .large: 14
            }
        }

        var padding: CGFloat {
            switch self {
            case .regular: 14
            case .small: 10
            case .large: 22
            }
        }
    }

    var role: Role = .primary
    var size: Size = .regular
    var hint: String?

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, style: self)
    }

    private struct Styled: View {
        let configuration: Configuration
        let style: KortexButtonStyle
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8)
            HStack(spacing: 6) {
                configuration.label.font(.grotesk(style.size.fontSize, .medium))
                if let hint = style.hint {
                    Text(hint).font(.grotesk(11)).foregroundStyle(hintColor)
                }
            }
            .foregroundStyle(labelColor)
            .lineLimit(1)
            .padding(.horizontal, style.size.padding)
            .frame(height: style.size.height)
            .background(fill, in: shape)
            .overlay { if style.role == .secondary { shape.strokeBorder(Color.kEdge) } }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        }

        private var fill: Color {
            switch style.role {
            case .primary: .kSynapse
            case .secondary: .kPanel
            case .destructive: .kAlarm
            }
        }

        private var labelColor: Color { style.role == .secondary ? .kInk : .kVoid }

        private var hintColor: Color { style.role == .secondary ? .kMuted : .kVoid }
    }
}

extension ButtonStyle where Self == KortexButtonStyle {
    static var kortexPrimary: KortexButtonStyle { KortexButtonStyle(role: .primary) }
    static var kortexSecondary: KortexButtonStyle { KortexButtonStyle(role: .secondary) }

    static func kortex(_ role: KortexButtonStyle.Role, size: KortexButtonStyle.Size = .regular, hint: String? = nil) -> KortexButtonStyle {
        KortexButtonStyle(role: role, size: size, hint: hint)
    }
}

/// The Figma "Segmented": a Panel track with an Edge hairline (radius 8), the selected segment
/// SynapseDim with a Synapse outline and label (radius 6), the others Muted. Words are Space Grotesk 12
/// on a 28pt track; `mono` is the compact one for short or counted labels ("3M", "ALL 5"), JetBrains
/// Mono 11 on 26pt. VoiceOver reads it as a picker.
struct KSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var mono = false

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)], mono: Bool = false) {
        self.title = title
        self._selection = selection
        self.options = options
        self.mono = mono
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i].0, options[i].1)
            }
        }
        .padding(2)
        .frame(height: mono ? 26 : 28)
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.kEdge))
        .fixedSize()
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
        }
    }

    private func segment(_ value: Value, _ label: String) -> some View {
        let selected = value == selection
        return Button { selection = value } label: {
            Text(label)
                .font(mono ? .mono(11) : .grotesk(12, .medium))
                .foregroundStyle(selected ? Color.kSynapse : Color.kMuted)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(selected ? Color.kSynapseDim : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.kSynapse : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Figma "Field": a Void box (radius 10, padding 14×10) with an Edge hairline that turns Synapse
/// while `focused`, a JetBrains Mono 10 caps label over the value. Values are Space Grotesk 15 Ink.
/// Use `KTextField`, `KDateField` and `KMenuField` for text, dates and choices; they track their own
/// focus. VoiceOver reads the field by its label. Fields fill the height of an `HStack` pair.
struct KField<Content: View>: View {
    let label: String
    var focused = false
    @ViewBuilder var content: Content

    init(_ label: String, focused: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.focused = focused
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).sectionLabelStyle().lineLimit(1).accessibilityHidden(true)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.kVoid, in: shape)
        .overlay(shape.strokeBorder(focused ? Color.kSynapse : Color.kEdge))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Two fields side by side, as the Figma pairs them (Amount | Date, Merchant | Paid with), the same
/// height. `trailingWidth` fixes the second one's width; nil splits the row evenly.
struct KFieldRow<Leading: View, Trailing: View>: View {
    var trailingWidth: CGFloat? = 200
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            if let trailingWidth { trailing.frame(width: trailingWidth) } else { trailing }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A `KField` holding a text field: Space Grotesk 15 Ink, the prompt Muted. `font` for numbers
/// (`.mono(13)`), `axis: .vertical` for a note that grows up to `lines`.
struct KTextField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var font: Font = .grotesk(15)
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int> = 1...1

    @FocusState private var focused: Bool

    init(_ label: String, text: Binding<String>, prompt: String = "", font: Font = .grotesk(15), axis: Axis = .horizontal, lines: ClosedRange<Int> = 1...1) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.font = font
        self.axis = axis
        self.lines = lines
    }

    var body: some View {
        KField(label, focused: focused) {
            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Color.kMuted), axis: axis)
                .labelsHidden()
                .textFieldStyle(.plain)
                .lineLimit(lines)
                .font(font)
                .foregroundStyle(Color.kInk)
                .focused($focused)
        }
    }
}

/// A `KField` holding a date: typed in place, or picked from the calendar behind the icon.
/// `latest` keeps it from going past a day (today, for things that already happened).
struct KDateField: View {
    let label: String
    @Binding var selection: Date
    var latest: Date?

    @FocusState private var focused: Bool
    @State private var calendar = false

    init(_ label: String, selection: Binding<Date>, latest: Date? = nil) {
        self.label = label
        self._selection = selection
        self.latest = latest
    }

    var body: some View {
        KField(label, focused: focused) {
            HStack(spacing: 8) {
                picker.datePickerStyle(.field).font(.grotesk(15)).focused($focused)
                Spacer(minLength: 0)
                Button { calendar = true } label: {
                    Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(Color.kMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose \(label.lowercased()) from a calendar")
                .popover(isPresented: $calendar, arrowEdge: .bottom) {
                    picker.datePickerStyle(.graphical).padding(12)
                }
            }
        }
    }

    @ViewBuilder private var picker: some View {
        if let latest {
            DatePicker(label, selection: $selection, in: ...latest, displayedComponents: .date).labelsHidden()
        } else {
            DatePicker(label, selection: $selection, displayedComponents: .date).labelsHidden()
        }
    }
}

/// A `KField` holding a choice: the chosen `value` and an up/down chevron, opening a menu of
/// `options` (tagged views, as in a `Picker`). A nil `value` shows "Choose…" in Muted.
struct KMenuField<Value: Hashable, Options: View>: View {
    let label: String
    @Binding var selection: Value
    let value: String?
    @ViewBuilder var options: Options

    @FocusState private var focused: Bool

    init(_ label: String, selection: Binding<Value>, value: String?, @ViewBuilder options: () -> Options) {
        self.label = label
        self._selection = selection
        self.value = value
        self.options = options()
    }

    var body: some View {
        KField(label, focused: focused) {
            Menu {
                Picker(label, selection: $selection) { options }
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                HStack(spacing: 8) {
                    Text(value ?? "Choose…")
                        .font(.grotesk(15))
                        .foregroundStyle(value == nil ? Color.kMuted : Color.kInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.kMuted)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focused($focused)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "None chosen")
        }
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
