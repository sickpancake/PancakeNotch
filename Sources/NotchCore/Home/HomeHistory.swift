/// The editor's bounded undo and redo history.
public struct HomeHistory: Sendable, Equatable {
    private var undoStack: [HomeLayout] = []
    private var redoStack: [HomeLayout] = []
    public init() {}
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// A new edit starts a fresh redo path.
    public mutating func record(_ before: HomeLayout) {
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        redoStack.removeAll()
    }
    public mutating func undo(current: HomeLayout) -> HomeLayout? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current); return previous
    }
    public mutating func redo(current: HomeLayout) -> HomeLayout? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current); return next
    }
}

extension HomeSettings {
    /// Refused edits and unchanged layouts do not use an undo step.
    @discardableResult public func edit(_ history: inout HomeHistory,
        _ change: (HomeLayout) -> Result<HomeLayout, HomeEditRefusal>) -> HomeEditRefusal? {
        let before = layout
        let refusal = apply(change(before))
        if layout != before { history.record(before) }
        return refusal
    }
}
