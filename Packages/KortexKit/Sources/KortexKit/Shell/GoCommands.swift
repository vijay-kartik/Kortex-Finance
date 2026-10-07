import SwiftUI

/// The Go menu: jumps between sidebar destinations with ⌘1 – ⌘5.
public struct GoCommands: Commands {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandMenu("Go") {
            ForEach(Destination.allCases) { destination in
                if let key = destination.shortcut {
                    Button(destination.title) { model.destination = destination }
                        .keyboardShortcut(key, modifiers: .command)
                } else {
                    Button(destination.title) { model.destination = destination }
                }
            }
        }
    }
}
