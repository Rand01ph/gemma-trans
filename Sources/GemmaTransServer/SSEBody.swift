import Foundation
import FlyingFox
import FlyingSocks

/// 把 AsyncStream<Data> 适配成 FlyingFox 需要的 AsyncBufferedSequence<UInt8>，
/// 配合 HTTPBodySequence(from:)（不带 count）实现 chunked/SSE 输出。
struct SSEBody: AsyncBufferedSequence, Sendable {
    typealias Element = UInt8
    let stream: AsyncStream<Data>

    func makeAsyncIterator() -> Iterator { Iterator(inner: stream.makeAsyncIterator()) }

    struct Iterator: AsyncBufferedIteratorProtocol {
        var inner: AsyncStream<Data>.AsyncIterator
        var pending: ArraySlice<UInt8> = []

        mutating func next() async -> UInt8? {
            if pending.isEmpty {
                guard let data = await inner.next() else { return nil }
                pending = ArraySlice(data)
            }
            return pending.popFirst()
        }

        mutating func nextBuffer(suggested count: Int) async -> ArraySlice<UInt8>? {
            if !pending.isEmpty {
                defer { pending = [] }
                return pending
            }
            guard let data = await inner.next() else { return nil }
            return ArraySlice(data)
        }
    }
}

enum SSE {
    static func event(_ json: Any) -> Data {
        let payload = (try? JSONSerialization.data(withJSONObject: json))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Data("data: \(payload)\n\n".utf8)
    }
    static let done = Data("data: [DONE]\n\n".utf8)
    static let headers: HTTPHeaders = [
        .contentType: "text/event-stream",
        HTTPHeader("Cache-Control"): "no-cache",
    ]
}
