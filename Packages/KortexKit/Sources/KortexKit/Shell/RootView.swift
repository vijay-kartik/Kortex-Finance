import KortexCloud
import SwiftUI

/// The main window: sign-in until someone is signed in, then the sidebar and the selected screen.
public struct RootView: View {
    @Bindable private var model: AppModel
    private let session: CloudSession

    public init(model: AppModel, session: CloudSession) {
        self.model = model
        self.session = session
    }

    public var body: some View {
        Group {
            switch session.state {
            case .starting:
                Color.kVoid.ignoresSafeArea()
            case .signedOut, .signingIn:
                SignInView(session: session)
            case .signedIn(let user):
                NavigationSplitView {
                    SidebarView(selection: $model.destination, finance: session.finance, user: user, open: model.open, signOut: session.signOut)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 232, max: 280)
                } detail: {
                    detail
                        .toolbarBackground(Color.kVoid, for: .windowToolbar)
                        .toolbarBackground(.visible, for: .windowToolbar)
                }
                .sheet(item: $model.sheet) { sheet in
                    SheetHost(sheet: sheet, finance: session.finance, model: model, close: { model.sheet = nil })
                }
                .modifier(ReceiptDropTarget(model: model))
            }
        }
        .preferredColorScheme(.dark)
        .tint(.kSynapse)
    }

    @ViewBuilder private var detail: some View {
        switch model.destination {
        case .dashboard: DashboardView(finance: session.finance, appModel: model, go: { model.destination = $0 })
        case .expenses: ExpensesView(finance: session.finance, model: model, go: { model.destination = $0 })
        case .accounts: AccountsView(finance: session.finance, model: model)
        case .cards: CardsView(finance: session.finance, model: model)
        case .pending: PendingView(finance: session.finance, model: model, go: { model.destination = $0 })
        case .recurring: RecurringView(finance: session.finance, model: model)
        case .categories: CategoriesView(finance: session.finance, model: model)
        case .reports: ReportsView(finance: session.finance, model: model)
        }
    }
}
