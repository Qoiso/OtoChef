import XCTest
@testable import OtoChefApp

final class ManagedRuntimeTests: XCTestCase {
    func testPathsKeepManagedEnvironmentInsideProjectRoot() {
        let paths = ManagedRuntimePaths(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))

        XCTAssertEqual(paths.root.path, "/tmp/OtoChef/.otochef-runtime")
        XCTAssertEqual(paths.micromamba.path, "/tmp/OtoChef/.otochef-runtime/bin/micromamba")
        XCTAssertEqual(paths.environment.path, "/tmp/OtoChef/.otochef-runtime/envs/otochef")
        XCTAssertEqual(paths.python.path, "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/python")
        XCTAssertEqual(paths.ffmpeg.path, "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/ffmpeg")
        XCTAssertEqual(paths.ytDLP.path, "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/yt-dlp")
        XCTAssertEqual(paths.deno.path, "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/deno")
        XCTAssertEqual(paths.stateFile.path, "/tmp/OtoChef/.otochef-runtime/runtime-state.json")
    }

    func testStatusIsReadyOnlyWhenEveryManagedToolExists() {
        let paths = ManagedRuntimePaths(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))
        let existingPaths = Set([
            paths.micromamba.path,
            paths.python.path,
            paths.ffmpeg.path,
            paths.ytDLP.path,
            paths.deno.path,
            paths.stateFile.path
        ])

        XCTAssertEqual(paths.status(fileExists: existingPaths.contains), .ready)
        XCTAssertEqual(paths.status(fileExists: { $0 != paths.ytDLP.path }), .missing)
    }

    func testToolsCanBeVerifiedBeforeReadyStateIsWritten() {
        let paths = ManagedRuntimePaths(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))
        let existingTools = Set([
            paths.micromamba.path,
            paths.python.path,
            paths.ffmpeg.path,
            paths.ytDLP.path,
            paths.deno.path
        ])

        XCTAssertTrue(paths.requiredToolsExist(fileExists: existingTools.contains))
        XCTAssertEqual(paths.status(fileExists: existingTools.contains), .missing)
    }

    func testApplyingManagedRuntimeUsesDirectPythonAndManagedTools() {
        let paths = ManagedRuntimePaths(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))

        let settings = AppSettings.defaults.applyingManagedRuntime(paths)

        XCTAssertEqual(settings.conda.environmentPath, paths.environment.path)
        XCTAssertEqual(settings.tools.ffmpegPath, paths.ffmpeg.path)
        XCTAssertEqual(settings.tools.ytDLPPath, paths.ytDLP.path)
    }

    func testInstallerEnvironmentKeepsHomeAndCachesInsideManagedRuntime() {
        let paths = ManagedRuntimePaths(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))

        let environment = ManagedRuntimeInstaller.processEnvironment(
            paths: paths,
            base: ["PATH": "/usr/bin", "HOME": "/Users/example", "SECRET": "hidden"]
        )

        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["HOME"], "/tmp/OtoChef/.otochef-runtime/home")
        XCTAssertEqual(environment["MAMBA_ROOT_PREFIX"], "/tmp/OtoChef/.otochef-runtime")
        XCTAssertEqual(environment["XDG_CACHE_HOME"], "/tmp/OtoChef/.otochef-runtime/cache")
        XCTAssertNil(environment["SECRET"])
    }
}
