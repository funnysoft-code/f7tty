import Foundation

public enum SplitAxis: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum SplitDirection: String, Codable, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

public enum PaneDropZone: String, Codable, Equatable, Sendable {
    case left
    case right
    case top
    case bottom
    case center
    case invalid
}

public enum WorkspaceModelError: Error, Equatable, LocalizedError, Sendable {
    case emptyName
    case emptyDirectory
    case emptyPaneTree
    case duplicateWorkspaceID(UUID)
    case duplicateSessionID(UUID)
    case duplicateTerminalID(UUID)
    case missingTerminalReference(UUID)
    case missingWorkspaceReference(UUID)
    case missingSessionReference(UUID)
    case invalidSessionSelection(UUID)
    case invalidSplitRatio(Double)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "A workspace or session name cannot be empty."
        case .emptyDirectory:
            return "A workspace or session directory cannot be empty."
        case .emptyPaneTree:
            return "A session must contain at least one terminal pane."
        case .duplicateWorkspaceID(let id):
            return "The saved layout contains duplicate workspace ID \(id)."
        case .duplicateSessionID(let id):
            return "The saved layout contains duplicate session ID \(id)."
        case .duplicateTerminalID(let id):
            return "The saved layout contains duplicate terminal ID \(id)."
        case .missingTerminalReference(let id):
            return "The pane tree references missing terminal ID \(id)."
        case .missingWorkspaceReference(let id):
            return "The selected workspace \(id) does not exist."
        case .missingSessionReference(let id):
            return "The selected session \(id) does not exist."
        case .invalidSessionSelection(let id):
            return "The selected session \(id) is not in the selected workspace."
        case .invalidSplitRatio(let ratio):
            return "The split ratio \(ratio) must be finite and between zero and one."
        case .unsupportedSchemaVersion(let version):
            return "The saved layout uses unsupported schema version \(version)."
        }
    }
}

public indirect enum PaneTree: Codable, Equatable, Sendable {
    case terminal(UUID)
    case split(axis: SplitAxis, ratio: Double, first: PaneTree, second: PaneTree)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case axis
        case ratio
        case first
        case second
    }

    private enum NodeType: String, Codable {
        case terminal
        case split
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded: PaneTree
        switch try container.decode(NodeType.self, forKey: .type) {
        case .terminal:
            decoded = .terminal(try container.decode(UUID.self, forKey: .id))
        case .split:
            decoded = .split(
                axis: try container.decode(SplitAxis.self, forKey: .axis),
                ratio: try container.decode(Double.self, forKey: .ratio),
                first: try container.decode(PaneTree.self, forKey: .first),
                second: try container.decode(PaneTree.self, forKey: .second)
            )
        }
        self = decoded
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let id):
            try container.encode(NodeType.terminal, forKey: .type)
            try container.encode(id, forKey: .id)
        case .split(let axis, let ratio, let first, let second):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(axis, forKey: .axis)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }

    public var leafIDs: [UUID] {
        switch self {
        case .terminal(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.leafIDs + second.leafIDs
        }
    }

    public var leafCount: Int {
        switch self {
        case .terminal:
            return 1
        case .split(_, _, let first, let second):
            return first.leafCount + second.leafCount
        }
    }

    public func contains(terminalID: UUID) -> Bool {
        switch self {
        case .terminal(let id):
            return id == terminalID
        case .split(_, _, let first, let second):
            return first.contains(terminalID: terminalID) || second.contains(terminalID: terminalID)
        }
    }

    public func validate(referencing knownTerminalIDs: Set<UUID>? = nil) throws {
        var seen = Set<UUID>()
        try collectTerminalIDs(into: &seen, knownTerminalIDs: knownTerminalIDs)
    }

    private func collectTerminalIDs(into seen: inout Set<UUID>, knownTerminalIDs: Set<UUID>?) throws {
        switch self {
        case .terminal(let id):
            guard seen.insert(id).inserted else {
                throw WorkspaceModelError.duplicateTerminalID(id)
            }
            if let knownTerminalIDs, !knownTerminalIDs.contains(id) {
                throw WorkspaceModelError.missingTerminalReference(id)
            }
        case .split(let axis, let ratio, let first, let second):
            _ = axis
            guard ratio.isFinite, ratio > 0, ratio < 1 else {
                throw WorkspaceModelError.invalidSplitRatio(ratio)
            }
            try first.collectTerminalIDs(into: &seen, knownTerminalIDs: knownTerminalIDs)
            try second.collectTerminalIDs(into: &seen, knownTerminalIDs: knownTerminalIDs)
        }
    }

    fileprivate func replacingTerminal(
        _ terminalID: UUID,
        with replacement: PaneTree
    ) -> PaneTree? {
        switch self {
        case .terminal(let id):
            return id == terminalID ? replacement : nil
        case .split(let axis, let ratio, let first, let second):
            if let replaced = first.replacingTerminal(terminalID, with: replacement) {
                return .split(axis: axis, ratio: ratio, first: replaced, second: second)
            }
            if let replaced = second.replacingTerminal(terminalID, with: replacement) {
                return .split(axis: axis, ratio: ratio, first: first, second: replaced)
            }
            return nil
        }
    }

    fileprivate func removingTerminal(_ terminalID: UUID) -> PaneTree? {
        switch self {
        case .terminal(let id):
            return id == terminalID ? nil : self
        case .split(let axis, let ratio, let first, let second):
            if first.contains(terminalID: terminalID) {
                guard let replacement = first.removingTerminal(terminalID) else { return second }
                return .split(axis: axis, ratio: ratio, first: replacement, second: second)
            }
            if second.contains(terminalID: terminalID) {
                guard let replacement = second.removingTerminal(terminalID) else { return first }
                return .split(axis: axis, ratio: ratio, first: first, second: replacement)
            }
            return self
        }
    }

    fileprivate func swappingTerminals(_ firstID: UUID, _ secondID: UUID) -> PaneTree {
        switch self {
        case .terminal(let id):
            if id == firstID { return .terminal(secondID) }
            if id == secondID { return .terminal(firstID) }
            return self
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: first.swappingTerminals(firstID, secondID),
                second: second.swappingTerminals(firstID, secondID)
            )
        }
    }
}

public struct WorkspaceSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var usesAutomaticTitle = false
    public var directory: String
    public var tree: PaneTree
    public var zoomedTerminalID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case usesAutomaticTitle
        case directory
        case tree
    }

    public init(
        id: UUID = UUID(),
        name: String,
        directory: String,
        terminalID: UUID = UUID(),
        tree: PaneTree? = nil
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.tree = tree ?? .terminal(terminalID)
        self.zoomedTerminalID = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        usesAutomaticTitle = try container.decodeIfPresent(Bool.self, forKey: .usesAutomaticTitle) ?? false
        directory = try container.decode(String.self, forKey: .directory)
        tree = try container.decode(PaneTree.self, forKey: .tree)
        zoomedTerminalID = nil
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(usesAutomaticTitle, forKey: .usesAutomaticTitle)
        try container.encode(directory, forKey: .directory)
        try container.encode(tree, forKey: .tree)
    }

    public var terminalIDs: [UUID] { tree.leafIDs }

    public func displayTitle(liveTitle: String?) -> String {
        guard usesAutomaticTitle else { return name }
        let title = liveTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return URL(fileURLWithPath: directory).lastPathComponent
    }

    public func contains(terminalID: UUID) -> Bool {
        tree.contains(terminalID: terminalID)
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceModelError.emptyName
        }
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceModelError.emptyDirectory
        }
        try tree.validate()
        if let zoomedTerminalID, !contains(terminalID: zoomedTerminalID) {
            throw WorkspaceModelError.missingTerminalReference(zoomedTerminalID)
        }
    }

    @discardableResult
    public mutating func split(
        terminalID: UUID,
        direction: SplitDirection,
        newTerminalID: UUID = UUID()
    ) -> Bool {
        guard contains(terminalID: terminalID), !contains(terminalID: newTerminalID) else { return false }
        let axis: SplitAxis
        switch direction {
        case .left, .right: axis = .horizontal
        case .up, .down: axis = .vertical
        }
        let newTerminal = PaneTree.terminal(newTerminalID)
        let replacement: PaneTree
        switch direction {
        case .left, .up:
            replacement = .split(axis: axis, ratio: 0.5, first: newTerminal, second: .terminal(terminalID))
        case .right, .down:
            replacement = .split(axis: axis, ratio: 0.5, first: .terminal(terminalID), second: newTerminal)
        }
        guard let newTree = tree.replacingTerminal(terminalID, with: replacement) else { return false }
        tree = newTree
        zoomedTerminalID = nil
        return true
    }

    @discardableResult
    public mutating func remove(terminalID: UUID) -> Bool {
        guard tree.leafCount > 1, contains(terminalID: terminalID), let newTree = tree.removingTerminal(terminalID) else {
            return false
        }
        tree = newTree
        if zoomedTerminalID == terminalID {
            zoomedTerminalID = nil
        }
        return true
    }

    @discardableResult
    public mutating func move(
        terminalID: UUID,
        to targetTerminalID: UUID,
        zone: PaneDropZone
    ) -> Bool {
        guard terminalID != targetTerminalID,
              contains(terminalID: terminalID),
              contains(terminalID: targetTerminalID) else { return false }

        if zone == .center {
            tree = tree.swappingTerminals(terminalID, targetTerminalID)
            return true
        }

        guard let withoutMovedTerminal = tree.removingTerminal(terminalID),
              withoutMovedTerminal.contains(terminalID: targetTerminalID),
              let newTree = withoutMovedTerminal.inserting(
                terminalID: terminalID,
                at: targetTerminalID,
                zone: zone
              ) else {
            return false
        }
        tree = newTree
        return true
    }

    @discardableResult
    public mutating func toggleZoom(for terminalID: UUID) -> Bool {
        guard contains(terminalID: terminalID) else { return false }
        zoomedTerminalID = zoomedTerminalID == terminalID ? nil : terminalID
        return true
    }

    @discardableResult
    public mutating func setRatio(at path: [Int], to ratio: Double) -> Bool {
        guard ratio.isFinite, ratio > 0, ratio < 1,
              let newTree = tree.settingRatio(at: path, to: ratio) else { return false }
        tree = newTree
        return true
    }

    @discardableResult
    public mutating func equalizeSplits() -> Bool {
        guard tree.leafCount > 1 else { return false }
        tree = tree.equalized
        return true
    }
}

private extension PaneTree {
    func settingRatio(at path: [Int], to ratio: Double) -> PaneTree? {
        switch self {
        case .terminal:
            return nil
        case .split(let axis, let currentRatio, let first, let second):
            guard let firstPath = path.first else {
                return .split(axis: axis, ratio: ratio, first: first, second: second)
            }
            let remainingPath = Array(path.dropFirst())
            if firstPath == 0, let updated = first.settingRatio(at: remainingPath, to: ratio) {
                return .split(axis: axis, ratio: currentRatio, first: updated, second: second)
            }
            if firstPath == 1, let updated = second.settingRatio(at: remainingPath, to: ratio) {
                return .split(axis: axis, ratio: currentRatio, first: first, second: updated)
            }
            return nil
        }
    }

    var equalized: PaneTree {
        switch self {
        case .terminal:
            return self
        case .split(let axis, _, let first, let second):
            return .split(axis: axis, ratio: 0.5, first: first.equalized, second: second.equalized)
        }
    }

    func inserting(terminalID: UUID, at targetTerminalID: UUID, zone: PaneDropZone) -> PaneTree? {
        guard zone != .center, zone != .invalid else { return nil }

        switch self {
        case .terminal(let id):
            guard id == targetTerminalID else { return nil }
            let moved = PaneTree.terminal(terminalID)
            let target = PaneTree.terminal(targetTerminalID)
            switch zone {
            case .left:
                return .split(axis: .horizontal, ratio: 0.5, first: moved, second: target)
            case .right:
                return .split(axis: .horizontal, ratio: 0.5, first: target, second: moved)
            case .top:
                return .split(axis: .vertical, ratio: 0.5, first: moved, second: target)
            case .bottom:
                return .split(axis: .vertical, ratio: 0.5, first: target, second: moved)
            case .center, .invalid:
                return nil
            }
        case .split(let axis, let ratio, let first, let second):
            if let replacement = first.inserting(terminalID: terminalID, at: targetTerminalID, zone: zone) {
                return .split(axis: axis, ratio: ratio, first: replacement, second: second)
            }
            if let replacement = second.inserting(terminalID: terminalID, at: targetTerminalID, zone: zone) {
                return .split(axis: axis, ratio: ratio, first: first, second: replacement)
            }
            return nil
        }
    }
}

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var directory: String
    public var sessions: [WorkspaceSession]
    /// Optional for compatibility with workspace files created before color preferences.
    public var appColor: String? = nil

    public init(
        id: UUID = UUID(),
        name: String,
        directory: String,
        sessions: [WorkspaceSession] = []
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.sessions = sessions
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceModelError.emptyName
        }
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceModelError.emptyDirectory
        }

        var sessionIDs = Set<UUID>()
        var terminalIDs = Set<UUID>()
        for session in sessions {
            guard sessionIDs.insert(session.id).inserted else {
                throw WorkspaceModelError.duplicateSessionID(session.id)
            }
            try session.validate()
            for terminalID in session.terminalIDs {
                guard terminalIDs.insert(terminalID).inserted else {
                    throw WorkspaceModelError.duplicateTerminalID(terminalID)
                }
            }
        }
    }

    @discardableResult
    public mutating func append(session: WorkspaceSession) -> Bool {
        guard !sessions.contains(where: { $0.id == session.id }),
              !sessions.flatMap(\.terminalIDs).contains(where: { session.terminalIDs.contains($0) }) else {
            return false
        }
        sessions.append(session)
        return true
    }

    public var nextSessionName: String {
        let names = Set(sessions.map(\.name))
        var number = 1
        while names.contains("Terminal \(number)") { number += 1 }
        return "Terminal \(number)"
    }

    @discardableResult
    public mutating func removeSession(id: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        sessions.remove(at: index)
        return true
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var workspaces: [Workspace]
    public var selectedWorkspaceID: UUID?
    public var selectedSessionID: UUID?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaces
        case selectedWorkspaceID
        case selectedSessionID
    }

    public init(
        schemaVersion: Int = WorkspaceState.currentSchemaVersion,
        workspaces: [Workspace],
        selectedWorkspaceID: UUID? = nil,
        selectedSessionID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionID = selectedSessionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        workspaces = try container.decode([Workspace].self, forKey: .workspaces)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw WorkspaceModelError.unsupportedSchemaVersion(schemaVersion)
        }

        var workspaceIDs = Set<UUID>()
        var sessionIDs = Set<UUID>()
        var terminalIDs = Set<UUID>()
        for workspace in workspaces {
            guard workspaceIDs.insert(workspace.id).inserted else {
                throw WorkspaceModelError.duplicateWorkspaceID(workspace.id)
            }
            try workspace.validate()
            for session in workspace.sessions {
                guard sessionIDs.insert(session.id).inserted else {
                    throw WorkspaceModelError.duplicateSessionID(session.id)
                }
                for terminalID in session.terminalIDs {
                    guard terminalIDs.insert(terminalID).inserted else {
                        throw WorkspaceModelError.duplicateTerminalID(terminalID)
                    }
                }
            }
        }

        if let selectedWorkspaceID {
            guard let workspace = workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
                throw WorkspaceModelError.missingWorkspaceReference(selectedWorkspaceID)
            }
            if let selectedSessionID {
                guard workspace.sessions.contains(where: { $0.id == selectedSessionID }) else {
                    throw WorkspaceModelError.invalidSessionSelection(selectedSessionID)
                }
            }
        } else if let selectedSessionID {
            throw WorkspaceModelError.missingSessionReference(selectedSessionID)
        }
    }

    public static func fresh(directory: String, workspaceName: String? = nil) -> WorkspaceState {
        let folderName = URL(fileURLWithPath: directory).standardizedFileURL.lastPathComponent
        let name = workspaceName ?? (folderName.isEmpty ? directory : folderName)
        let session = WorkspaceSession(name: "Terminal", directory: directory)
        let workspace = Workspace(name: name, directory: directory, sessions: [session])
        return WorkspaceState(
            workspaces: [workspace],
            selectedWorkspaceID: workspace.id,
            selectedSessionID: session.id
        )
    }

    /// Reordering changes ownership/order only, never terminal identities or directories.
    @discardableResult
    public mutating func reorderSidebar(source: UUID, target: UUID, after: Bool) -> Bool {
        guard source != target else { return false }
        if let from = workspaces.firstIndex(where: { $0.id == source }),
           workspaces.contains(where: { $0.id == target }) {
            let moved = workspaces.remove(at: from)
            let destination = workspaces.firstIndex(where: { $0.id == target })!
            workspaces.insert(moved, at: destination + (after ? 1 : 0))
            return true
        }
        guard let from = workspaces.firstIndex(where: { $0.sessions.contains(where: { $0.id == source }) }),
              let index = workspaces[from].sessions.firstIndex(where: { $0.id == source }) else { return false }
        if let destination = workspaces.firstIndex(where: { $0.id == target }), from != destination {
            let moved = workspaces[from].sessions.remove(at: index)
            workspaces[destination].sessions.append(moved)
            if selectedSessionID == source { selectedWorkspaceID = target }
            return true
        }
        guard let destination = workspaces.firstIndex(where: { $0.sessions.contains(where: { $0.id == target }) }) else { return false }
        let moved = workspaces[from].sessions.remove(at: index)
        let targetIndex = workspaces[destination].sessions.firstIndex(where: { $0.id == target })!
        workspaces[destination].sessions.insert(moved, at: targetIndex + (after ? 1 : 0))
        if selectedSessionID == source { selectedWorkspaceID = workspaces[destination].id }
        return true
    }
}

public enum WorkspacePersistenceError: Error, LocalizedError {
    case invalidSavedState(URL, String)
    case saveBlockedByInvalidState(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidSavedState(let url, let reason):
            return "F7TTY could not load \(url.path): \(reason). The file was retained so it can be recovered."
        case .saveBlockedByInvalidState(let url):
            return "F7TTY will not overwrite invalid saved state at \(url.path). Move or remove the file after reviewing it."
        }
    }
}

public enum WorkspaceLoadResult {
    case missing
    case loaded(WorkspaceState)
    case invalid(WorkspacePersistenceError)
}

public final class WorkspacePersistence {
    public let fileURL: URL

    private let fileManager: FileManager
    private var retainedInvalidState = false

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func applicationSupportURL(fileManager: FileManager = .default) -> URL? {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportURL
            .appendingPathComponent("F7TTY", isDirectory: true)
            .appendingPathComponent("workspace-state.json", isDirectory: false)
    }

    public var hasRetainedInvalidState: Bool { retainedInvalidState }

    public func load() -> WorkspaceLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            retainedInvalidState = false
            return .missing
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
            try state.validate()
            retainedInvalidState = false
            return .loaded(state)
        } catch {
            retainedInvalidState = true
            let failure = WorkspacePersistenceError.invalidSavedState(fileURL, error.localizedDescription)
            return .invalid(failure)
        }
    }

    public func save(_ state: WorkspaceState) throws {
        guard !retainedInvalidState else {
            throw WorkspacePersistenceError.saveBlockedByInvalidState(fileURL)
        }
        try state.validate()

        let parentURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let data = try encodedData(for: state)
        let temporaryURL = parentURL.appendingPathComponent(".workspace-state-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    public func discardRetainedInvalidState() {
        retainedInvalidState = false
    }

    private func encodedData(for state: WorkspaceState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }
}
