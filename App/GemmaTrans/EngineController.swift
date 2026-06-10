import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let shared = EngineController()

    private(set) var status: Status = .loading
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    let settings = AppSettings.load()

    func start() {
        status = .loading
        Task {
            let engine = TranslationEngine(settings: settings)
            do {
                try await engine.load()
                self.engine = engine
                let port = settings.port
                self.serverTask = Task.detached {
                    try await APIServer(translator: engine, port: port).run()
                }
                self.status = .ready
            } catch {
                self.status = .failed("\(error)")
            }
        }
    }
}
