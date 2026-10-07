import KortexCloud
import KortexFinance
import SwiftUI

/// The Mac/Sidebar component from Figma: Overview and Plan destinations, then the synced accounts and
/// cards with their balances, and the signed-in account at the bottom.
struct SidebarView: View {
    @Binding var selection: Destination
    let finance: FinanceSync
    let user: CloudUser
    let open: (Account) -> Void
    let signOut: () -> Void

    @State private var confirmingReset = false
    @State private var resetting = false
    @State private var resetError: String?
    /// What deleted accounts left behind, waiting on Remove's confirmation.
    @State private var leftovers: AccountRules.Leftovers?

    var body: some View {
        List(selection: Binding($selection)) {
            Section {
                ForEach(Destination.overview) { row($0) }
            } header: {
                Text("OVERVIEW").sectionLabelStyle()
            }
            Section {
                ForEach(Destination.plan) { row($0) }
            } header: {
                Text("PLAN").sectionLabelStyle()
            }
            let data = finance.data
            if !data.moneyAccounts.isEmpty {
                Section {
                    ForEach(data.moneyAccounts) { ledgerRow($0, data: data) }
                } header: {
                    Text("ACCOUNTS").sectionLabelStyle()
                }
            }
            if !data.cards.isEmpty {
                Section {
                    ForEach(data.cards) { ledgerRow($0, data: data) }
                } header: {
                    HStack {
                        Text("CARDS").sectionLabelStyle()
                        Spacer(minLength: 4)
                        if data.cards.contains(where: { $0.kind == .creditCard }) {
                            Text(sidebarAmount(data.cardsOutstandingMinor))
                                .font(.mono(11))
                                .foregroundStyle(Color.kMuted.opacity(0.8))
                                .help("Outstanding on all your credit cards")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.kSidebar)
        .safeAreaInset(edge: .bottom) { accountFooter }
        .confirmationDialog("Erase all your data?", isPresented: $confirmingReset) {
            Button("Erase All Data", role: .destructive) { reset() }
        } message: {
            Text("\(resetSummary)Everything is erased here and on your phone, and receipt images are removed from this Mac. You stay signed in. This can't be undone.")
        }
        .confirmationDialog(leftovers.map(leftoversTitle) ?? "",
                            isPresented: Binding(get: { leftovers.map { !$0.isEmpty } ?? false }, set: { if !$0 { leftovers = nil } })) {
            Button("Remove", role: .destructive) {
                finance.apply(AccountRules.removeLeftovers(in: finance.data))
                leftovers = nil
            }
        } message: {
            Text(leftovers.map(leftoversMessage) ?? "")
        }
        .alert("Nothing to remove", isPresented: Binding(get: { leftovers?.isEmpty == true }, set: { if !$0 { leftovers = nil } })) {
            Button("OK") { leftovers = nil }
        } message: {
            Text("No entries or bills are left from deleted accounts.")
        }
        .alert("Couldn't reset your data", isPresented: Binding(get: { resetError != nil }, set: { if !$0 { resetError = nil } })) {
            Button("OK") { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
    }

    private func row(_ destination: Destination) -> some View {
        Label {
            Text(destination.title).font(.grotesk(13, selection == destination ? .medium : .regular))
        } icon: {
            Image(systemName: destination.symbol)
        }
        .tag(destination)
    }

    /// Opens the account in Accounts, or the card in Cards.
    private func ledgerRow(_ account: Account, data: FinanceData) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(account.kind.isCard ? cardTitle(account) : account.name)
                    .font(.grotesk(13))
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbol(for: account.kind))
            }
            .foregroundStyle(Color.kMuted)
            Spacer(minLength: 4)
            Text(sidebarAmount(data.balanceMinor(of: account)))
                .font(.mono(11))
                .foregroundStyle(Color.kMuted.opacity(0.8))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(account) }
    }

    /// "₹1,45,000", or with paise when there are some.
    private func sidebarAmount(_ minor: Int64) -> String {
        Money.format(minor).replacingOccurrences(of: ".00", with: "")
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            Text(user.initials)
                .font(.grotesk(11, .medium))
                .foregroundStyle(Color.kSynapse)
                .frame(width: 28, height: 28)
                .background(Color.kSynapseDim, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? user.email ?? "Signed in")
                    .font(.grotesk(12, .medium))
                    .foregroundStyle(Color.kInk)
                    .lineLimit(1)
                if let error = finance.writeError {
                    Text("Couldn't save: \(error)").font(.grotesk(11)).foregroundStyle(Color.kAlarm).lineLimit(2).help(error)
                } else {
                    SyncStatusLine(status: finance.status)
                }
            }
            Spacer(minLength: 0)
            Menu {
                if let email = user.email { Text(email) }
                Button("Sign Out", action: signOut)
                Divider()
                Button("Remove Entries of Deleted Accounts…") {
                    let data = finance.data
                    leftovers = AccountRules.leftovers(of: AccountRules.deletedAccountUids(in: data), in: data)
                }
                Button("Reset Data…", role: .destructive) { confirmingReset = true }
                    .disabled(resetting)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kSidebar)
        .overlay(alignment: .top) { Rectangle().fill(Color.kEdge).frame(height: 1) }
    }

    private func leftoversTitle(_ l: AccountRules.Leftovers) -> String {
        l.entries.isEmpty ? "Tidy up entries of deleted accounts?"
            : "Remove \(l.entries.count == 1 ? "1 entry" : "\(l.entries.count) entries") of deleted accounts?"
    }

    /// What Remove does, part by part.
    private func leftoversMessage(_ l: AccountRules.Leftovers) -> String {
        var parts: [String] = []
        if !l.entries.isEmpty { parts.append("Their entries are removed here and on your phone.") }
        if !l.bills.isEmpty { parts.append("\(l.bills.count == 1 ? "1 bill" : "\(l.bills.count) bills") of deleted cards \(l.bills.count == 1 ? "goes" : "go") too.") }
        if !l.relabeled.isEmpty {
            let n = l.relabeled.count
            parts.append("\(n == 1 ? "1 transfer or payment" : "\(n) transfers and payments") with accounts you still have "
                + "\(n == 1 ? "stays" : "stay"), shown as from an unknown account instead, so those balances don't change.")
        }
        return parts.joined(separator: " ") + " This can't be undone."
    }

    /// "3 accounts and cards, 240 entries and 4 recurring payments." for the confirmation.
    private var resetSummary: String {
        let data = finance.data
        let custom = data.categories.values.filter { !$0.builtIn }.count
        let parts = [(data.accounts.count, "account or card", "accounts and cards"), (data.transactions.count, "entry", "entries"),
                     (data.recurring.count, "recurring payment", "recurring payments"), (custom, "category", "categories")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        guard !parts.isEmpty else { return "" }
        return (parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!) + ". "
    }

    private func reset() {
        resetting = true
        Task {
            do {
                try await finance.eraseAll()
                ReceiptStore.removeAll()
            } catch {
                resetError = error.localizedDescription
            }
            resetting = false
        }
    }

    private func cardTitle(_ card: Account) -> String {
        card.last4.map { "\(card.name) ••\($0)" } ?? card.name
    }

    private func symbol(for kind: AccountKind) -> String {
        switch kind {
        case .bank: "building.columns"
        case .cash: "banknote"
        case .wallet: "wallet.bifold"
        case .creditCard, .debitCard: "creditcard"
        }
    }
}

struct SyncStatusLine: View {
    let status: FinanceSync.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.grotesk(11)).foregroundStyle(Color.kMuted).lineLimit(1)
        }
    }

    private var text: String {
        switch status {
        case .idle: "Not syncing"
        case .loading: "Syncing…"
        case .live: "Synced"
        case .offline: "Offline · saved data"
        case .failed: "Sync failed"
        }
    }

    private var color: Color {
        switch status {
        case .live: .kGrowth
        case .loading, .offline: .kAmber
        case .failed: .kAlarm
        case .idle: .kMuted
        }
    }
}
