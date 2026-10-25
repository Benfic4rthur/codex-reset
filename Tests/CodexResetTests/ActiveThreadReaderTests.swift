import Foundation
import SQLite3
import XCTest
@testable import CodexReset

final class ActiveThreadReaderTests: XCTestCase {
    private func fixture() throws -> ProjectReaderFixture {
        let fixture = try ProjectReaderFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.directory) }
        return fixture
    }

    func testDesktopAssignmentNamesAnActiveWorktreeOutsideTheRegisteredRoot() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        let worktree = fixture.path("managed-worktrees/run/Example")
        try fixture.addProject("canonical", name: "Example Project", root: source)
        try fixture.addThread(cwd: worktree)
        try fixture.writeState(assignment: "legacy", projects: ["legacy": fixture.project("legacy", name: "Example Project", root: source)])

        let thread = try XCTUnwrap(fixture.read().first)
        XCTAssertEqual(thread.projectName, "Example Project")
        XCTAssertEqual(thread.model, "gpt-6.1-sol")
        XCTAssertEqual(thread.effort, "ultra")
    }

    func testExplicitDatabaseProjectWinsOverDesktopAssignmentAndCwd() throws {
        let fixture = try fixture()
        let otherRoot = fixture.path("projects/Other")
        try fixture.addProject("explicit", name: "Explicit Project", root: fixture.path("projects/Explicit"))
        try fixture.addProject("other", name: "Other Project", root: otherRoot)
        try fixture.addThread(cwd: otherRoot, projectID: "explicit")
        try fixture.writeState(assignment: "legacy-other", projects: ["legacy-other": fixture.project("legacy-other", name: "Desktop Project", root: otherRoot)])

        XCTAssertEqual(try fixture.read().first?.projectName, "Explicit Project")
    }

    func testLegacyAssignmentUsesCanonicalProjectNameAndSeesRenamesOnNextRead() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Source")
        try fixture.addProject("canonical", name: "Current Name", root: source)
        try fixture.addThread(cwd: fixture.path("managed-worktrees/run/Source"))
        try fixture.writeState(assignment: "legacy", projects: ["legacy": fixture.project("legacy", name: "Old Name", root: source)], migration: ["legacy": "canonical"])
        XCTAssertEqual(try fixture.read().first?.projectName, "Current Name")

        try fixture.stateSQL("UPDATE projects SET name = 'Renamed Project' WHERE id = 'canonical';")
        XCTAssertEqual(try fixture.read().first?.projectName, "Renamed Project")
    }

    func testRootFallbackUsesTheMostSpecificProjectAndRespectsPathBoundaries() throws {
        let fixture = try fixture()
        let root = fixture.path("projects/Example")
        let nested = fixture.path("projects/Example/Library")
        try fixture.addProject("outer", name: "Outer Project", root: root)
        try fixture.addProject("inner", name: "Inner Project", root: nested)
        try fixture.addThread(id: "nested", cwd: nested.appendingPathComponent("Sources"))
        try fixture.addThread(id: "exact", cwd: root)
        try fixture.addThread(id: "sibling", cwd: fixture.path("projects/Example-Other"))

        let names = Dictionary(uniqueKeysWithValues: try fixture.read().map { ($0.id, $0.projectName) })
        XCTAssertEqual(names["nested"], "Inner Project")
        XCTAssertEqual(names["exact"], "Outer Project")
        XCTAssertEqual(names["sibling"], "")
    }

    func testMissingOrCorruptOptionalDesktopStateDoesNotHideActiveThreads() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        try fixture.addProject("known", name: "Known Project", root: source)
        try fixture.addThread(cwd: source.appendingPathComponent("Sources"))
        XCTAssertEqual(try fixture.read().first?.projectName, "Known Project")

        try Data("{ invalid JSON".utf8).write(to: fixture.root.appendingPathComponent(".codex-global-state.json"))
        XCTAssertEqual(try fixture.read().first?.projectName, "Known Project")
        try fixture.stateSQL("UPDATE threads SET cwd = '/unregistered/location', project_id = NULL;")
        XCTAssertEqual(try fixture.read().first?.projectName, "")
    }

    func testChangingDesktopAssignmentIsReflectedWithoutRestartingTheReader() throws {
        let fixture = try fixture()
        let first = fixture.path("projects/First")
        let second = fixture.path("projects/Second")
        try fixture.addThread(cwd: fixture.path("managed-worktrees/run"))
        let projects = ["first": fixture.project("first", name: "First Project", root: first),
                        "second": fixture.project("second", name: "Second Project", root: second)]
        try fixture.writeState(assignment: "first", projects: projects)
        XCTAssertEqual(try fixture.read().first?.projectName, "First Project")
        try fixture.writeState(assignment: "second", projects: projects)
        XCTAssertEqual(try fixture.read().first?.projectName, "Second Project")
    }

    func testExplicitProjectlessThreadDoesNotInheritItsCwdProject() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        try fixture.addProject("known", name: "Known Project", root: source)
        try fixture.addThread(cwd: source.appendingPathComponent("Sources"))
        try fixture.writeState(projectless: ["thread"])

        XCTAssertEqual(try fixture.read().first?.projectName, "")
    }

    func testExplicitProjectlessMembershipWinsOverAStaleDesktopAssignment() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        try fixture.addProject("known", name: "Known Project", root: source)
        try fixture.addThread(cwd: source.appendingPathComponent("Sources"))
        try fixture.writeState(assignment: "legacy", projects: ["legacy": fixture.project("legacy", name: "Stale Project", root: source)], projectless: ["thread"])

        XCTAssertEqual(try fixture.read().first?.projectName, "")
        try fixture.stateSQL("UPDATE threads SET project_id = 'known';")
        XCTAssertEqual(try fixture.read().first?.projectName, "Known Project")
    }

    func testRemoteDesktopAssignmentCannotNameALocalActiveThread() throws {
        let fixture = try fixture()
        try fixture.addThread(cwd: fixture.path("unregistered"))
        try fixture.writeState(assignment: "remote-project", projects: ["remote-project": fixture.project("remote-project", name: "Remote Project", root: fixture.path("remote"))], host: "remote-host")

        XCTAssertEqual(try fixture.read().first?.projectName, "")
    }

    func testWorktreeWithoutDesktopAssignmentResolvesThroughGitCommonDirectory() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        let worktree = fixture.path("managed-worktrees/run/Example")
        try fixture.addProject("known", name: "Worktree Project", root: source)
        try fixture.makeWorktree(worktree, source: source)
        try fixture.addThread(cwd: worktree.appendingPathComponent("Sources"))

        XCTAssertEqual(try fixture.read().first?.projectName, "Worktree Project")
    }

    func testWorktreeResolvesRelativeGitDirectoryAndRelativeCommonDirectory() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        let worktree = fixture.path("managed-worktrees/run/Example")
        try fixture.addProject("known", name: "Relative Worktree Project", root: source)
        try fixture.makeWorktree(worktree, source: source)
        try Data("gitdir: ../../../projects/Example/.git/worktrees/fixture\n".utf8)
            .write(to: worktree.appendingPathComponent(".git"))
        try fixture.addThread(cwd: worktree.appendingPathComponent("Sources/Feature"))

        XCTAssertEqual(try fixture.read().first?.projectName, "Relative Worktree Project")
    }

    func testDanglingDatabaseProjectCanFallBackToDesktopAssociation() throws {
        let fixture = try fixture()
        let source = fixture.path("projects/Example")
        try fixture.addThread(cwd: fixture.path("managed-worktrees/run"), projectID: "removed-project")
        try fixture.writeState(assignment: "legacy", projects: ["legacy": fixture.project("legacy", name: "Associated Project", root: source)])

        XCTAssertEqual(try fixture.read().first?.projectName, "Associated Project")
    }
}

private final class ProjectReaderFixture {
    let directory: URL
    let root: URL

    init() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        directory = project.appendingPathComponent(".build/project-reader-tests-" + UUID().uuidString, isDirectory: true)
        root = directory.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try stateSQL("""
            CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT, updated_at_ms INTEGER);
            CREATE TABLE project_roots (project_id TEXT, path TEXT, position INTEGER);
            CREATE TABLE threads (
                id TEXT PRIMARY KEY, name TEXT, title TEXT, cwd TEXT, project_id TEXT,
                model TEXT, reasoning_effort TEXT, agent_path TEXT, thread_source TEXT,
                source TEXT, tokens_used INTEGER, rollout_path TEXT, archived INTEGER
            );
            """)
        try execute("""
            CREATE TABLE thread_turns (
                thread_id TEXT, turn_id TEXT, status TEXT, started_at INTEGER, rollout_ordinal INTEGER
            );
            """, database: root.appendingPathComponent("thread_history_1.sqlite"))
    }

    func path(_ relative: String) -> URL { directory.appendingPathComponent(relative, isDirectory: true) }

    func addProject(_ id: String, name: String, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try stateSQL("""
            INSERT INTO projects (id, name, updated_at_ms) VALUES (\(quote(id)), \(quote(name)), 1000);
            INSERT INTO project_roots (project_id, path, position) VALUES (\(quote(id)), \(quote(root.path)), 0);
            """)
    }

    func addThread(id: String = "thread", cwd: URL, projectID: String? = nil) throws {
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try stateSQL("""
            INSERT INTO threads VALUES (
                \(quote(id)), 'Fixture conversation', 'Fixture title', \(quote(cwd.path)), \(quote(projectID)),
                'gpt-6.1-sol', 'ultra', NULL, 'cli', 'cli', 123, '', 0
            );
            """)
        try execute("""
            INSERT INTO thread_turns VALUES (\(quote(id)), \(quote("turn-" + id)), 'inProgress', 1800000000, 1);
            """, database: root.appendingPathComponent("thread_history_1.sqlite"))
    }

    func project(_ id: String, name: String, root: URL) -> [String: Any] {
        ["id": id, "name": name, "rootPaths": [root.path]]
    }

    func writeState(assignment: String? = nil, projects: [String: [String: Any]] = [:],
                    migration: [String: String] = [:], projectless: [String] = [], host: String = "local") throws {
        var state: [String: Any] = [
            "local-projects": projects,
            "projectless-thread-ids": projectless,
            "app-server-project-id-by-legacy-project-id-by-host": ["local:" + root.path: migration]
        ]
        if let assignment {
            state["thread-project-assignments"] = ["thread": ["projectKind": "local", "projectId": assignment]]
            state["thread-project-membership-host-ids"] = ["thread": host]
        }
        try JSONSerialization.data(withJSONObject: state).write(to: root.appendingPathComponent(".codex-global-state.json"))
    }

    func makeWorktree(_ worktree: URL, source: URL) throws {
        let common = source.appendingPathComponent(".git", isDirectory: true)
        let administration = common.appendingPathComponent("worktrees/fixture", isDirectory: true)
        for directory in [common.appendingPathComponent("objects"), common.appendingPathComponent("refs/heads"), administration, worktree] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("gitdir: \(administration.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        try Data("../..\n".utf8).write(to: administration.appendingPathComponent("commondir"))
        try Data("\(worktree.appendingPathComponent(".git").path)\n".utf8).write(to: administration.appendingPathComponent("gitdir"))
        try Data("ref: refs/heads/main\n".utf8).write(to: administration.appendingPathComponent("HEAD"))
        try Data("[core]\nrepositoryformatversion = 0\nbare = false\n".utf8).write(to: common.appendingPathComponent("config"))
    }

    func read() throws -> [ActiveThread] { try ActiveThreadReader.readThrowing(root: root) }
    func stateSQL(_ sql: String) throws { try execute(sql, database: root.appendingPathComponent("state_5.sqlite")) }

    private func quote(_ value: String?) -> String {
        value.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "NULL"
    }

    private func execute(_ sql: String, database: URL) throws {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let connection else { throw NSError(domain: "ProjectReaderFixture", code: 1) }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "ProjectReaderFixture", code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(connection))])
        }
    }
}
