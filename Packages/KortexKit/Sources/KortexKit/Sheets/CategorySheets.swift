import KortexCloud
import KortexFinance
import SwiftUI

/// New category and renaming / recolouring one of yours (Figma: Categories 02).
struct CategorySheet: View {
    let finance: FinanceSync
    let editing: SpendCategory?
    let close: () -> Void

    @State private var kind: CategoryKind
    @State private var name: String
    @State private var color: String
    @State private var error: String?

    static let colors = ["Synapse", "Teal", "Amber", "Lilac", "Rose", "Mint", "Sky", "Growth"]

    init(finance: FinanceSync, editing: SpendCategory?, kind: CategoryKind = .expense, close: @escaping () -> Void) {
        self.finance = finance
        self.editing = editing
        self.close = close
        _kind = State(initialValue: editing?.kind ?? kind)
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: editing?.colorToken ?? "Mint")
    }

    var body: some View {
        SheetChrome(
            title: editing == nil ? "New category" : "Edit \(editing!.name)",
            primary: editing == nil ? "Add category" : "Save changes",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            if editing == nil {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .expense ? "Shows up when you add an expense." : "Shows up when you add income.")
                        .font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
            Section {
                TextField("Name", text: $name, prompt: Text("Groceries"))
                LabeledContent("Colour") {
                    HStack(spacing: 8) {
                        ForEach(Self.colors, id: \.self) { token in
                            Button { color = token } label: {
                                Circle().fill(Color.token(token)).frame(width: 20, height: 20)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(color == token ? Color.kInk : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(token)
                        }
                    }
                }
            } footer: {
                Text("Kortex suggests it for merchants you file under it.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
        }
    }

    private func save() {
        let result = editing.map { CategoryRules.update($0.uid, name: name, colorToken: color, in: finance.data) }
            ?? CategoryRules.add(name: name, kind: kind, colorToken: color, in: finance.data)
        if let failure = finance.apply(result) { error = failure.message } else { close() }
    }
}

/// Delete category (Figma: Categories 03): its entries move to another category, or Uncategorised.
struct DeleteCategorySheet: View {
    let finance: FinanceSync
    let category: SpendCategory
    let close: () -> Void

    @State private var moveTo: String?
    @State private var error: String?

    var body: some View {
        let data = finance.data
        let count = data.transactions.values.filter { $0.categoryUid == category.uid }.count
        let targets = data.categories.values.filter { $0.kind == category.kind && $0.uid != category.uid }.sorted { $0.name < $1.name }
        SheetChrome(
            title: "Delete \(category.name)?",
            subtitle: count == 0 ? "No entries use it." : "\(count) entr\(count == 1 ? "y uses" : "ies use") it. They aren't deleted.",
            primary: "Delete category",
            destructive: true,
            error: error,
            onCancel: close,
            onPrimary: {
                if let failure = finance.apply(CategoryRules.delete(category.uid, moveTo: moveTo, in: finance.data)) { error = failure.message } else { close() }
            }
        ) {
            Picker("Move its entries to", selection: $moveTo) {
                Text("Uncategorised").tag(String?.none)
                ForEach(targets) { Text($0.name).tag(String?.some($0.uid)) }
            }
        }
    }
}
