from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/Agent/CacheClient.swift").read_text()
agent = (root / "Sources/Agent/Agent.swift").read_text()
model = source[source.index("struct CacheReply:") : source.index("func runPreferenceCommand(")]
runner = source[source.index("func runCacheHelper(") :]
failure_handler = agent[agent.index("    private func stopOnError(") : agent.index("    private func audit(")]
failure_handler = failure_handler.replace("private func stopOnError", "func stopOnError", 1)
stubs = '''
func readNativePrefetch() -> Int? { 13 }
func nativePreferenceDomain() -> String { "/nonexistent/FotoBudget-test" }
@MainActor final class FailureHarness {
    let defaults = UserDefaults(suiteName: "PhotosStorage-tests-" + UUID().uuidString)!
    var automatic: Bool { defaults.bool(forKey: "automatic") }
    var pendingRequest: (rounds: Int, allowPurge: Bool)?
    var accessProblem: String?
    var state = AgentState()
    var status: String { get { state.message } set { state.message = newValue } }
'''
with tempfile.TemporaryDirectory(prefix="fotobudget-helper-tests-") as directory:
    main = Path(directory) / "main.swift"
    binary = Path(directory) / "tests"
    main.write_text("import Foundation\nimport Darwin\n" + model + stubs + failure_handler + "}\n" + runner
                    + (root / "tests/HelperFailureTests.swift").read_text())
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-warnings-as-errors",
                    str(root / "Sources/Shared/ControlProtocol.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
