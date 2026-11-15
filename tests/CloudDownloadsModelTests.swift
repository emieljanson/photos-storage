import AppKit

@main
struct CloudDownloadsModelTests {
    @MainActor
    static func main() async {
        let model = CloudDownloadsModel()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        model.inspect([folder.appendingPathComponent("first.txt"), folder.appendingPathComponent("second.txt")])
        model.cancelRemaining()
        for _ in 0..<100 where model.busy {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !model.busy, model.rows.count == 2,
              model.rows.allSatisfy({ $0.message != "Checking iCloud…" }),
              model.ready.isEmpty else {
            fputs("FAIL: cancelled checks must stop showing progress and remain ineligible for removal\n", stderr)
            exit(1)
        }
        print("PASS cancelled checks stop showing progress without starting a file worker")
    }
}
