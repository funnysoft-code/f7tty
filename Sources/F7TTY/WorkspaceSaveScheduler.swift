import Foundation

/// Keeps at most one write in flight and one replaceable, not-yet-written snapshot.
/// Load the persistence instance before handing it off, then use it only through
/// this scheduler. Call `flush()` before the application finishes terminating.
@MainActor
final class WorkspaceSaveScheduler {
    private let queue = DispatchQueue(label: "pt.funnysoft.f7tty.workspace-save", qos: .utility)
    private let writer: Writer
    private let onError: @MainActor (Error) -> Void
    private let timer: DispatchSourceTimer
    private var pendingState: WorkspaceState?
    private var pendingDeadline = DispatchTime.now()
    private var activeWriteID: UUID?

    init(persistence: WorkspacePersistence, onError: @escaping @MainActor (Error) -> Void) {
        writer = Writer(persistence: persistence)
        self.onError = onError
        timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            self?.startPendingWrite()
        }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    /// Captures a value snapshot without validating, encoding, or touching disk.
    /// A positive delay debounces successive submissions, such as divider drags.
    /// An immediate submission also replaces any older debounced snapshot.
    func submit(_ state: WorkspaceState, delay: TimeInterval = 0) {
        pendingState = state
        pendingDeadline = .now() + (delay.isFinite ? max(0, delay) : 0)
        startPendingWrite()
    }

    /// Bypasses debounce and waits for the latest submitted snapshot to reach disk.
    /// Writes still run on the serial background queue; only this shutdown path
    /// blocks the caller. Throws if the latest write failed, even if its error was
    /// already delivered to `onError`. A newer successful write clears that error.
    func flush() throws {
        timer.schedule(deadline: .distantFuture)
        let state = pendingState
        pendingState = nil
        let hadActiveWrite = activeWriteID != nil
        activeWriteID = nil // Ignore completion callbacks already queued on main.

        let previousResult = queue.sync { writer.result }
        var finalResult = previousResult
        if let state {
            queue.async { [writer] in
                writer.save(state)
            }
            finalResult = queue.sync { writer.result }
        }

        // A failed in-flight write must still be surfaced if a newer snapshot
        // superseded it during flush. The final write's failure is thrown below.
        if hadActiveWrite, state != nil, case .failure(let error) = previousResult {
            onError(error)
        }
        try finalResult.get()
    }

    private func startPendingWrite() {
        timer.schedule(deadline: .distantFuture)
        guard activeWriteID == nil, let state = pendingState else { return }
        guard pendingDeadline <= .now() else {
            timer.schedule(deadline: pendingDeadline)
            return
        }

        pendingState = nil
        let id = UUID()
        activeWriteID = id
        queue.async { [writer, weak self] in
            let result = writer.save(state)
            DispatchQueue.main.async { [weak self] in
                self?.didFinishWrite(id: id, result: result)
            }
        }
    }

    private func didFinishWrite(id: UUID, result: Result<Void, Error>) {
        guard activeWriteID == id else { return }
        activeWriteID = nil
        startPendingWrite()
        if case .failure(let error) = result {
            onError(error)
        }
    }

    /// Mutable persistence/result access is confined to `queue`. The unchecked
    /// conformance transfers the existing, non-Sendable persistence instance
    /// without changing its atomic replacement or retained-invalid-state rules.
    private final class Writer: @unchecked Sendable {
        let persistence: WorkspacePersistence
        private(set) var result: Result<Void, Error> = .success(())

        init(persistence: WorkspacePersistence) {
            self.persistence = persistence
        }

        @discardableResult
        func save(_ state: WorkspaceState) -> Result<Void, Error> {
            result = Result { try persistence.save(state) }
            return result
        }
    }
}
