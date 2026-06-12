import Testing
@testable import GemmaTransKit

@Suite struct TextChunkerTests {
    /// 不超限文本原样返回（含空白，不做任何修剪）
    @Test func shortTextReturnedVerbatim() {
        #expect(TextChunker.split("Hello, world.", limit: 700) == ["Hello, world."])
        #expect(TextChunker.split("  a\n\nb  ", limit: 700) == ["  a\n\nb  "])
        // 恰好等于 limit 也原样
        let exact = String(repeating: "x", count: 10)
        #expect(TextChunker.split(exact, limit: 10) == [exact])
    }

    /// 空文本 → []
    @Test func emptyTextReturnsEmptyArray() {
        #expect(TextChunker.split("", limit: 700).isEmpty)
    }

    /// 段落（空行）优先切分 + 贪心装包：相邻小段合并到不超 limit，块内保留 \n\n
    @Test func splitsAtParagraphBoundariesWithGreedyPacking() {
        let p1 = String(repeating: "a", count: 300)
        let p2 = String(repeating: "b", count: 300)
        let p3 = String(repeating: "c", count: 300)
        let text = p1 + "\n\n" + p2 + "\n\n" + p3
        let chunks = TextChunker.split(text, limit: 700)
        // p1+p2 合并装入第一块（602 ≤ 700），p3 独立成块
        #expect(chunks == [p1 + "\n\n" + p2, p3])
    }

    /// 段内无空行时按换行切，整行不被腰斩，块内保留单个 \n
    @Test func splitsAtNewlinesKeepingLinesIntact() {
        let lines = (0..<10).map { _ in String(repeating: "x", count: 100) }
        let text = lines.joined(separator: "\n")  // 1009 字，无空行
        let chunks = TextChunker.split(text, limit: 350)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 350)
            // 每块由若干完整行组成（行长 100），无半行
            for line in chunk.split(separator: "\n") {
                #expect(line.count == 100)
            }
        }
    }

    /// 超长单段（无换行）按句末标点切，块边界落在句末
    @Test func splitsOverlongParagraphAtSentenceEnds() {
        let en = (1...40).map { "This is sentence \($0)." }.joined(separator: " ")
        let enChunks = TextChunker.split(en, limit: 300)
        #expect(enChunks.count > 1)
        for chunk in enChunks {
            #expect(chunk.count <= 300)
            #expect(chunk.hasSuffix("."))
        }
        let zh = (1...60).map { "这是第\($0)句话。" }.joined()
        let zhChunks = TextChunker.split(zh, limit: 100)
        #expect(zhChunks.count > 1)
        for chunk in zhChunks {
            #expect(chunk.count <= 100)
            #expect(chunk.hasSuffix("。"))
        }
    }

    /// 无标点无换行的超长串：硬切成 ≤limit 的块，不丢字符
    @Test func hardCutsUnbreakableRun() {
        let text = String(repeating: "x", count: 1500)
        let chunks = TextChunker.split(text, limit: 700)
        #expect(chunks == [
            String(repeating: "x", count: 700),
            String(repeating: "x", count: 700),
            String(repeating: "x", count: 100),
        ])
    }

    /// 不变量：任何非空白字符不丢失、顺序不变；每块 ≤ limit
    @Test(arguments: [50, 120, 700])
    func nonWhitespaceLosslessInvariant(limit: Int) {
        let text = """
        GemmaTrans is an on-device translator. It runs Gemma locally!
        Does it stream? Yes — token by token.

        第二段是中文。包含句号。还有！以及？标点混排，数字 3.14 不该被腰斩。
        换行内嵌段落，继续写一些长内容来确保超过各档 limit 的长度，再加一点 padding text。

        Third paragraph has no trailing punctuation and a longish run xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx end.
        """
        let chunks = TextChunker.split(text, limit: limit)
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.count <= limit)
        }
        let joinedNonWS = chunks.joined().filter { !$0.isWhitespace }
        let originalNonWS = text.filter { !$0.isWhitespace }
        #expect(joinedNonWS == originalNonWS)
    }
}
