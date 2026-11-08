import Foundation

/// Prepares on-device text recognition when Tac opens, so it is ready before the shortcut is pressed.
/// Vision prepares its accurate models once per installed app version, which can take a minute or more.
@MainActor
final class TextRecognition: ObservableObject {
    enum State { case idle, preparing, ready, failed }

    static let shared = TextRecognition()

    @Published private(set) var state = State.idle
    var ready: Bool { state == .ready }

    private init() {}

    /// Starts preparing unless it is running or done. After a failure, the next call retries.
    func prepare() {
        guard state == .idle || state == .failed else { return }
        state = .preparing
        Task.detached(priority: .utility) { [weak self] in
            // Ready only once the sample text was actually read.
            let succeeded = TextLayout.warmUp()
            await MainActor.run { self?.state = succeeded ? .ready : .failed }
        }
    }
}
