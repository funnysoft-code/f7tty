// Foundation-only runner for the same disk-backed checks used by XCTest.
// Compile with swiftc -swift-version 5 -parse-as-library -DWORKSPACE_SAVE_STANDALONE
// Sources/F7TTY/WorkspaceModel.swift Sources/F7TTY/WorkspaceSaveScheduler.swift
// Tests/F7TTYTests/WorkspaceSaveSchedulerTests.swift Scripts/test-workspace-saves.swift
// -o <temporary-directory>/test-workspace-saves
import Foundation

@main
struct WorkspaceSaveRegressionRunner {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--baseline") {
            try await WorkspaceSaveSchedulerChecks.synchronousBaseline()
            return
        }

        try await WorkspaceSaveSchedulerChecks.rapidDividerChanges()
        print("PASS: 100 divider updates produce one durable background write")
        try await WorkspaceSaveSchedulerChecks.flushBypassesDebounce()
        print("PASS: flush bypasses a one-hour debounce and is idempotent")
        try await WorkspaceSaveSchedulerChecks.immediateSaveSupersedesDelayedSnapshot()
        print("PASS: immediate saves supersede older delayed snapshots")
        try await WorkspaceSaveSchedulerChecks.slowWriterPreservesLatestSnapshot()
        print("PASS: a blocked writer saves only the in-flight and latest pending snapshots in order")
        try await WorkspaceSaveSchedulerChecks.asyncFailureAndRecovery()
        print("PASS: asynchronous errors preserve the original file and later saves recover")
        try await WorkspaceSaveSchedulerChecks.flushSurfacesInFlightFailure()
        print("PASS: flush reports an in-flight failure even when the latest snapshot succeeds")
        try await WorkspaceSaveSchedulerChecks.retainedInvalidStateIsProtected()
        print("PASS: retained invalid state is protected byte-for-byte with its original error")
    }
}
