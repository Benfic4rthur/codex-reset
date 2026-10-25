import Foundation

/// Resolves display metadata only. Desktop state is optional and stays in memory.
struct ProjectResolver {
    struct Root {
        let projectID: String
        let path: String
    }

    private let names: [String: String]
    private let roots: [Root]
    private let desktop: DesktopProjectState
    private let hostKey: String

    init(codexHome: URL, names: [String: String], roots: [Root]) {
        self.names = names.compactMapValues(Self.nonempty)
        self.roots = roots
        hostKey = "local:" + codexHome.path
        desktop = (try? Data(contentsOf: codexHome.appendingPathComponent(".codex-global-state.json")))
            .flatMap { try? JSONDecoder().decode(DesktopProjectState.self, from: $0) } ?? DesktopProjectState()
    }

    func name(threadID: String, projectID: String, cwd: String) -> String? {
        if let name = names[projectID] { return name }

        // A desktop assignment survives worktree moves even when the thread's
        // app-server project_id has not been migrated yet.
        let localMembership = desktop.membershipHosts[threadID].map { $0 == "local" || $0 == hostKey } ?? true
        if localMembership && desktop.projectless.contains(threadID) { return nil }
        if localMembership, let assignment = desktop.assignments[threadID], assignment.projectKind == "local" {
            if let name = desktopName(assignment.projectId) { return name }
        }

        if let name = name(matching: cwd) { return name }
        if let origin = worktreeOrigin(cwd: cwd) { return name(matching: origin.path) }
        return nil
    }

    private func desktopName(_ id: String) -> String? {
        if let migrated = desktop.migrations[hostKey]?[id], let name = names[migrated] { return name }
        return names[id] ?? desktop.projects[id]?.name.flatMap(Self.nonempty)
    }

    private func name(matching cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        let directory = canonicalPath(cwd)
        var candidates: [(path: String, name: String, order: Int)] = []
        for (index, root) in roots.enumerated() {
            guard root.path.hasPrefix("/"), let name = names[root.projectID] else { continue }
            candidates.append((canonicalPath(root.path), name, index))
        }
        for id in desktop.projects.keys.sorted() {
            guard let name = desktopName(id) else { continue }
            for path in desktop.projects[id]?.rootPaths ?? [] where path.hasPrefix("/") {
                candidates.append((canonicalPath(path), name, candidates.count))
            }
        }
        return candidates.filter { root in
            directory == root.path || directory.hasPrefix(root.path == "/" ? "/" : root.path + "/")
        }.sorted {
            if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
            return $0.order < $1.order
        }.first?.name
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func worktreeOrigin(cwd: String) -> URL? {
        guard cwd.hasPrefix("/") else { return nil }
        var directory = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        // Only read Git administrative pointers; never inspect source or messages.
        while directory.path != "/" {
            let marker = directory.appendingPathComponent(".git")
            if let pointer = smallTextFile(marker), pointer.hasPrefix("gitdir:") {
                let relative = String(pointer.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !relative.isEmpty else { return nil }
                let gitDirectory = URL(fileURLWithPath: relative, relativeTo: directory).standardizedFileURL
                guard let common = smallTextFile(gitDirectory.appendingPathComponent("commondir")), !common.isEmpty else { return nil }
                let commonDirectory = URL(fileURLWithPath: common, relativeTo: gitDirectory).standardizedFileURL.resolvingSymlinksInPath()
                guard commonDirectory.lastPathComponent == ".git" else { return nil }
                return commonDirectory.deletingLastPathComponent()
            }
            // A normal repository boundary is not a linked worktree.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory), isDirectory.boolValue { return nil }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private func smallTextFile(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              size.isRegularFile == true, (size.fileSize ?? Int.max) <= 16_384,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonempty(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Unknown fields (including UI history) are never decoded or retained.
private struct DesktopProjectState: Decodable {
    struct Project: Decodable {
        let name: String?
        let rootPaths: [String]?
    }
    struct Assignment: Decodable {
        let projectKind: String
        let projectId: String
    }
    var projects: [String: Project] = [:]
    var assignments: [String: Assignment] = [:]
    var membershipHosts: [String: String] = [:]
    var migrations: [String: [String: String]] = [:]
    var projectless: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case projects = "local-projects"
        case assignments = "thread-project-assignments"
        case membershipHosts = "thread-project-membership-host-ids"
        case migrations = "app-server-project-id-by-legacy-project-id-by-host"
        case projectless = "projectless-thread-ids"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projects = (try? values.decode([String: Project].self, forKey: .projects)) ?? [:]
        assignments = (try? values.decode([String: Assignment].self, forKey: .assignments)) ?? [:]
        membershipHosts = (try? values.decode([String: String].self, forKey: .membershipHosts)) ?? [:]
        migrations = (try? values.decode([String: [String: String]].self, forKey: .migrations)) ?? [:]
        projectless = (try? values.decode(Set<String>.self, forKey: .projectless)) ?? []
    }
}
