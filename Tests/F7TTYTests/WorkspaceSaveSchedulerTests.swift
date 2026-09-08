import Foundation

#if !WORKSPACE_SAVE_STANDALONE
import XCTest
@testable import F7TTY

final class WorkspaceSaveSchedulerTests: XCTestCase {
    func testRapidDividerChangesPersistOnlyLatestSnapshot() async throws {
        try await WorkspaceSaveSchedulerChecks.rapidDividerChanges()
    }

    func testFlushBypassesDebounceAndIsIdempotent() async throws {
        try await WorkspaceSaveSchedulerChecks.flushBypassesDebounce()
    }

    func testImmediateSaveSupersedesDelayedSnapshot() async throws {
        try await WorkspaceSaveSchedulerChecks.immediateSaveSupersedesDelayedSnapshot()
    }

    func testSlowWriterKeepsOnlyLatestPendingSnapshotInOrder() async throws {
        try await WorkspaceSaveSchedulerChecks.slowWriterPreservesLatestSnapshot()
    }

    func testAsyncFailurePreservesFileAndNextSaveRecovers() async throws {
        try await WorkspaceSaveSchedulerChecks.asyncFailureAndRecovery()
    }

    func testFlushSurfacesSupersededInFlightFailure() async throws {
        try await WorkspaceSaveSchedulerChecks.flushSurfacesInFlightFailure()
    }

    func testRetainedInvalidStateCannotBeOverwritten() async throws {
        try await WorkspaceSaveSchedulerChecks.retainedInvalidStateIsProtected()
    }
}
#endif

// Shared with Scripts/test-workspace-saves.swift so these same disk-backed
// regressions can run with Command Line Tools, where XCTest is unavailable.
@MainActor
enum WorkspaceSaveSchedulerChecks {
    static func rapidDividerChanges() async throws {
        try await withWorkspaceFile { url in
            let initial = splitState()
            try WorkspacePersistence(fileURL: url).save(initial)
            let files = RecordingWorkspaceFileManager()
            var errors: [Error] = []
            let scheduler = WorkspaceSaveScheduler(
                persistence: WorkspacePersistence(fileURL: url, fileManager: files),
                onError: { errors.append($0) }
            )
            defer { try? scheduler.flush() }

            var latest = initial
            for step in 1...100 {
                latest.workspaces[0].sessions[0].setRatio(at: [], to: 0.2 + Double(step) * 0.006)
                scheduler.submit(latest, delay: 0.025)
            }
            try require(try load(url) == initial, "Debounced submissions wrote before the debounce elapsed")
            try await waitUntil { !files.savedStates.isEmpty }
            try scheduler.flush()
            try require(try load(url) == latest, "The final divider ratio was not durable")
            try require(files.savedStates == [latest], "A divider burst wrote intermediate snapshots")
            try require(!files.savedOnMainThread, "Persistence ran on the UI thread")
            try require(errors.isEmpty, "A valid divider burst reported an error")
            try requireNoTemporaryFiles(at: url)
        }
    }

    static func flushBypassesDebounce() async throws {
        try await withWorkspaceFile { url in
            let files = RecordingWorkspaceFileManager()
            let scheduler = WorkspaceSaveScheduler(
                persistence: WorkspacePersistence(fileURL: url, fileManager: files),
                onError: { _ in }
            )
            defer { try? scheduler.flush() }

            try scheduler.flush()
            try require(!FileManager.default.fileExists(atPath: url.path), "An idle flush created a file")
            var state = splitState()
            let submitted = state
            scheduler.submit(state, delay: 3_600)
            state.workspaces[0].name = "Not submitted"
            try scheduler.flush()
            try scheduler.flush()
            try require(try load(url) == submitted, "Flush did not persist the captured snapshot immediately")
            try require(files.savedStates == [submitted], "An idempotent flush wrote again")
            try require(!files.savedOnMainThread, "Flush performed persistence on the UI thread")
            try requireNoTemporaryFiles(at: url)
        }
    }

    static func immediateSaveSupersedesDelayedSnapshot() async throws {
        try await withWorkspaceFile { url in
            let files = RecordingWorkspaceFileManager()
            let scheduler = WorkspaceSaveScheduler(
                persistence: WorkspacePersistence(fileURL: url, fileManager: files),
                onError: { _ in }
            )
            defer { try? scheduler.flush() }

            let older = splitState()
            var latest = older
            latest.workspaces[0].name = "Immediate selection change"
            scheduler.submit(older, delay: 0.025)
            scheduler.submit(latest)
            try scheduler.flush()
            // Let the superseded timer and queued completion get a turn.
            try await Task.sleep(nanoseconds: 60_000_000)
            try scheduler.flush()
            try require(try load(url) == latest, "An old timer overwrote the immediate snapshot")
            try require(files.savedStates == [latest], "The superseded delayed snapshot was written")
        }
    }

    static func slowWriterPreservesLatestSnapshot() async throws {
        try await withWorkspaceFile { url in
            let gate = WorkspaceWriteGate()
            let files = RecordingWorkspaceFileManager(beforeFirstWrite: { try gate.holdWriter() })
            let scheduler = WorkspaceSaveScheduler(
                persistence: WorkspacePersistence(fileURL: url, fileManager: files),
                onError: { _ in }
            )
            defer { gate.open(); try? scheduler.flush() }

            let first = splitState()
            scheduler.submit(first)
            try gate.waitForWriter()
            var latest = first
            for step in 1...100 {
                latest.workspaces[0].name = "Change \(step)"
                scheduler.submit(latest)
            }
            gate.open()
            try scheduler.flush()
            try require(try load(url) == latest, "An older in-flight write won over the latest snapshot")
            try require(files.savedStates == [first, latest], "A slow writer accumulated intermediate writes")

            var afterFlush = latest
            afterFlush.workspaces[0].name = "After flush"
            scheduler.submit(afterFlush, delay: 3_600)
            try scheduler.flush()
            try await Task.sleep(nanoseconds: 25_000_000)
            try scheduler.flush()
            try require(try load(url) == afterFlush, "A stale completion changed the state after flush")
            try require(files.savedStates == [first, latest, afterFlush], "Flush or stale completions duplicated writes")
            try require(!files.savedOnMainThread, "The serial writer used the UI thread")
            try requireNoTemporaryFiles(at: url)
        }
    }

    static func asyncFailureAndRecovery() async throws {
        try await withWorkspaceFile { url in
            let initial = splitState()
            try WorkspacePersistence(fileURL: url).save(initial)
            var errors: [Error] = []
            let scheduler = WorkspaceSaveScheduler(persistence: WorkspacePersistence(fileURL: url)) { error in
                MainActor.preconditionIsolated()
                errors.append(error)
            }
            defer { try? scheduler.flush() }

            var invalid = initial
            invalid.workspaces[0].name = ""
            scheduler.submit(invalid)
            try await waitUntil { !errors.isEmpty }
            try require(errors.count == 1, "The asynchronous failure was reported more than once")
            try require(errors[0] as? WorkspaceModelError == .emptyName, "The original validation error was lost")
            try require(try load(url) == initial, "Invalid new state replaced the previous valid file")
            do {
                try scheduler.flush()
                throw WorkspaceSaveCheckFailure("Flush forgot the latest failed write")
            } catch let error as WorkspaceModelError {
                try require(error == .emptyName, "Flush changed the original validation error")
            }

            var recovered = initial
            recovered.workspaces[0].name = "Recovered"
            scheduler.submit(recovered)
            try scheduler.flush()
            try scheduler.flush()
            try require(try load(url) == recovered, "A failed write prevented later valid persistence")
            try require(errors.count == 1, "Flush repeated an already-delivered error callback")
            try requireNoTemporaryFiles(at: url)
        }
    }

    static func flushSurfacesInFlightFailure() async throws {
        try await withWorkspaceFile { url in
            let initial = splitState()
            try WorkspacePersistence(fileURL: url).save(initial)
            let gate = WorkspaceWriteGate()
            let files = RecordingWorkspaceFileManager(beforeFirstWrite: {
                try gate.holdWriter()
                throw WorkspaceSaveInjectedFailure.writeDenied
            })
            var errors: [Error] = []
            let scheduler = WorkspaceSaveScheduler(
                persistence: WorkspacePersistence(fileURL: url, fileManager: files),
                onError: { errors.append($0) }
            )
            defer { gate.open(); try? scheduler.flush() }

            scheduler.submit(initial)
            try gate.waitForWriter()
            var latest = initial
            latest.workspaces[0].name = "Newer successful write"
            scheduler.submit(latest, delay: 3_600)
            gate.open()
            try scheduler.flush()
            try await Task.sleep(nanoseconds: 25_000_000)
            try require(errors.count == 1, "Flush swallowed or duplicated the superseded in-flight failure")
            try require(errors[0] as? WorkspaceSaveInjectedFailure == .writeDenied, "Flush changed the I/O error")
            try require(try load(url) == latest, "An earlier failure prevented the latest snapshot from saving")
            try require(files.savedStates == [latest], "A failed write changed the durable state")
            try scheduler.flush()
        }
    }

    static func retainedInvalidStateIsProtected() async throws {
        try await withWorkspaceFile { url in
            let original = Data("{ retained invalid workspace data".utf8)
            try original.write(to: url)
            let persistence = WorkspacePersistence(fileURL: url)
            guard case .invalid = persistence.load() else {
                throw WorkspaceSaveCheckFailure("The invalid-state fixture unexpectedly loaded")
            }
            let scheduler = WorkspaceSaveScheduler(persistence: persistence, onError: { _ in })
            defer { try? scheduler.flush() }
            scheduler.submit(splitState(), delay: 3_600)
            do {
                try scheduler.flush()
                throw WorkspaceSaveCheckFailure("Flush overwrote retained invalid state")
            } catch WorkspacePersistenceError.saveBlockedByInvalidState(let blockedURL) {
                try require(blockedURL == url, "The retained-invalid-state error lost its file URL")
            }
            try require(try Data(contentsOf: url) == original, "The retained invalid file was modified")
            try requireNoTemporaryFiles(at: url)
        }
    }

    /// Exercises the pre-scheduler call path without changing shared source files.
    static func synchronousBaseline() async throws {
        try await withWorkspaceFile { url in
            let files = RecordingWorkspaceFileManager()
            let persistence = WorkspacePersistence(fileURL: url, fileManager: files)
            var state = splitState()
            let start = Date()
            for step in 1...100 {
                state.workspaces[0].sessions[0].setRatio(at: [], to: 0.2 + Double(step) * 0.006)
                try persistence.save(state)
            }
            try require(try load(url) == state, "The synchronous baseline did not save its final state")
            try require(files.savedStates.count == 100, "The baseline did not perform one write per update")
            print("BASELINE: 100 divider updates -> \(files.savedStates.count) durable writes; main thread: \(files.savedOnMainThread); elapsed: \(String(format: "%.3f", Date().timeIntervalSince(start)))s")
        }
    }

    private static func splitState() -> WorkspaceState {
        var state = WorkspaceState.fresh(directory: "/", workspaceName: "Workspace")
        let terminalID = state.workspaces[0].sessions[0].terminalIDs[0]
        state.workspaces[0].sessions[0].split(terminalID: terminalID, direction: .right)
        return state
    }

    private static func load(_ url: URL) throws -> WorkspaceState {
        try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: url))
    }

    private static func requireNoTemporaryFiles(at url: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        try require(names == [url.lastPathComponent], "Persistence left temporary files behind: \(names)")
    }

    private static func withWorkspaceFile(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("f7tty-workspace-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory.appendingPathComponent("workspace-state.json"))
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            try require(Date() < deadline, "Timed out waiting for background persistence")
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw WorkspaceSaveCheckFailure(message) }
    }
}

private struct WorkspaceSaveCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private enum WorkspaceSaveInjectedFailure: Error {
    case writeDenied
}

private final class WorkspaceWriteGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func holdWriter() throws {
        started.signal()
        guard released.wait(timeout: .now() + 5) == .success else {
            throw WorkspaceSaveCheckFailure("Timed out waiting to release the background writer")
        }
    }

    func waitForWriter() throws {
        guard started.wait(timeout: .now() + 5) == .success else {
            throw WorkspaceSaveCheckFailure("Submission did not start a background write")
        }
    }

    func open() { released.signal() }
}

/// Observes decoded bytes after real atomic moves/replacements, not scheduler
/// internals. The optional gate makes backpressure/failure ordering deterministic.
private final class RecordingWorkspaceFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private let beforeFirstWrite: (@Sendable () throws -> Void)?
    private var attempts = 0
    private var states: [WorkspaceState] = []
    private var usedMainThread = false

    init(beforeFirstWrite: (@Sendable () throws -> Void)? = nil) {
        self.beforeFirstWrite = beforeFirstWrite
        super.init()
    }

    var savedStates: [WorkspaceState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }

    var savedOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedMainThread
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        lock.lock()
        attempts += 1
        let isFirstWrite = attempts == 1
        usedMainThread = usedMainThread || Thread.isMainThread
        lock.unlock()
        if isFirstWrite { try beforeFirstWrite?() }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try super.moveItem(at: srcURL, to: dstURL)
        try recordSavedState(at: dstURL)
    }

    override func replaceItem(at originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String?, options: FileManager.ItemReplacementOptions = [], resultingItemURL resultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        try super.replaceItem(at: originalItemURL, withItemAt: newItemURL, backupItemName: backupItemName, options: options, resultingItemURL: resultingURL)
        try recordSavedState(at: originalItemURL)
    }

    private func recordSavedState(at url: URL) throws {
        let state = try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: url))
        lock.lock()
        states.append(state)
        lock.unlock()
    }
}
