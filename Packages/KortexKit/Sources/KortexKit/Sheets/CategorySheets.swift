import KortexFinance
import SwiftUI

/// New category and renaming / recolouring one of yours (Figma: Categories 02). Editing an expense
/// category adds its monthly budget; a built-in expense category shows only that, as on the phone.
struct CategorySheet: View {
    let finance: any FinanceStore
    let editing: SpendCategory?
    let close: () -> Void

    @State private var kind: CategoryKind
    @State private var name: String
    @State private var color: String
    /// Empty is no budget.
    @State private var budget: String
    @State private var error: String?

    static let colors = ["Synapse", "Teal", "Amber", "Lilac", "Rose", "Mint", "Sky", "Growth"]

    init(finance: any FinanceStore, editing: SpendCategory?, kind: CategoryKind = .expense, close: @escaping () -> Void) {
        self.finance = finance
        self.editing = editing
        self.close = close
        _kind = State(initialValue: editing?.kind ?? kind)
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: editing?.colorToken ?? "Mint")
        _budget = State(initialValue: editing.flatMap { finance.data.budgets[$0.uid] }.map { Money.editable($0.amountMinor) } ?? "")
    }

    /// New categories get their budget once they exist; income never has one.
    private var budgetable: Bool { editing?.kind == .expense }

    var body: some View {
        SheetChrome(
            title: editing.map { $0.builtIn ? $0.name : "Edit \($0.name)" } ?? "New category",
            primary: editing == nil ? "Add category" : "Save changes",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            if editing?.builtIn != true { fields }
            if budgetable {
                Section {
                    AmountField(label: "Monthly budget", text: $budget)
                } footer: {
                    Text(budgetFooter).font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
        }
    }

    private var budgetFooter: String {
        let month = LocalDay.today().yearMonth
        let spent = Spending.expenses(Array(finance.data.transactions.values), from: month.firstDay, to: month.lastDay)
            .filter { $0.categoryUid == editing?.uid }.reduce(0) { $0 + $1.amountMinor }
        return "\(Money.format(spent, wholeUnits: true)) spent this month. Resets on the 1st of each month; leave empty for no budget."
    }

    @ViewBuilder private var fields: some View {
        Group {
            if editing == nil {
                Section {
                    LabeledContent("Type") {
                        KSegmented("Type", selection: $kind, options: [(CategoryKind.expense, "Expense"), (.income, "Income")])
                    }
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

    /// The category and its budget go in one change, so the phone never syncs half of a save.
    private func save() {
        let data = finance.data
        var result: Result<Change, FinanceError>
        if let editing {
            result = editing.builtIn ? .success(Change([])) : CategoryRules.update(editing.uid, name: name, colorToken: color, in: data)
            if budgetable {
                let typed = budget.trimmingCharacters(in: .whitespaces)
                let budgetResult: Result<Change, FinanceError>
                if typed.isEmpty {
                    budgetResult = BudgetRules.clear(editing.uid, in: data)
                } else if let minor = Money.parseMinor(typed), minor > 0 {
                    budgetResult = minor == data.budgets[editing.uid]?.amountMinor ? .success(Change([])) : BudgetRules.set(editing.uid, amountMinor: minor, in: data)
                } else {
                    budgetResult = .failure(.invalidAmount)
                }
                result = result.flatMap { change in budgetResult.map { Change(change.writes + $0.writes) } }
            }
        } else {
            result = CategoryRules.add(name: name, kind: kind, colorToken: color, in: data)
        }
        if let failure = finance.apply(result) { error = failure.message } else { close() }
    }
}

/// Delete category (Figma: Categories 03): its entries move to another category, or Uncategorised.
struct DeleteCategorySheet: View {
    let finance: any FinanceStore
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
