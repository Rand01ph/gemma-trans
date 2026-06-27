import Foundation

/// 把长文本切成 ≤limit 字符的段落块，供逐段翻译。纯函数，无依赖，便于单测。
/// 切分优先级：空行（段落）> 换行 > 句末标点（。．.!?！？）> 硬切。
/// 贪心装包：相邻小段合并到不超过 limit；保持原文顺序；块内保留原有换行。
/// 不变量：任何非空白字符不丢失、顺序不变（块间分隔空白允许丢弃）；
/// 空文本 → []；text ≤ limit → [text]（原样，不修剪）。
public enum TextChunker {
    public static func split(_ text: String, limit: Int) -> [String] {
        precondition(limit > 0, "limit must be positive")
        if text.isEmpty { return [] }
        if text.count <= limit { return [text] }

        // 逐级细分：段落 → 行 → 句 → 硬切，直到每个原子段都装得进 limit
        var atoms: [Substring] = []
        for para in splitAfterNewlineRuns(text[...], minNewlines: 2) {
            if fits(para, limit) { atoms.append(para); continue }
            for line in splitAfterNewlineRuns(para, minNewlines: 1) {
                if fits(line, limit) { atoms.append(line); continue }
                for sentence in splitAfterSentenceEnds(line) {
                    if fits(sentence, limit) { atoms.append(sentence); continue }
                    atoms.append(contentsOf: hardCut(sentence, limit))
                }
            }
        }
        return pack(atoms, limit)
    }

    // MARK: - 装包

    /// 贪心装包：顺序合并相邻原子段，直到再装就超 limit。
    /// 原子段彼此首尾相接覆盖全文，故只在块边界 trim 空白——块内空白（含换行）原样保留。
    private static func pack(_ atoms: [Substring], _ limit: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }
        for atom in atoms {
            let candidate = current + atom
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).count <= limit {
                current = candidate
            } else {
                flush()
                current = String(atom)
            }
        }
        flush()
        return chunks
    }

    /// 修剪首尾空白后是否装得进 limit（尾随分隔空白会在块边界被 trim 掉，不计长度）
    private static func fits(_ s: Substring, _ limit: Int) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).count <= limit
    }

    // MARK: - 各级切分（分隔空白归前段，保证段落首尾相接、全文无损）

    /// 在「含 ≥minNewlines 个换行的最大空白串」之后切开。
    /// minNewlines=2 即空行（段落边界），=1 即普通换行（行边界）。
    private static func splitAfterNewlineRuns(_ s: Substring, minNewlines: Int) -> [Substring] {
        var parts: [Substring] = []
        var segStart = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i].isNewline else { i = s.index(after: i); continue }
            // 吃掉整串空白（含换行与行间空格），统计换行数
            var j = i
            var newlines = 0
            while j < s.endIndex, s[j].isWhitespace {
                if s[j].isNewline { newlines += 1 }
                j = s.index(after: j)
            }
            if newlines >= minNewlines {
                parts.append(s[segStart..<j])
                segStart = j
            }
            i = j
        }
        if segStart < s.endIndex { parts.append(s[segStart..<s.endIndex]) }
        return parts
    }

    private static let sentenceEnders: Set<Character> = ["。", "．", ".", "!", "?", "！", "？"]
    /// CJK 句末标点无条件成立；ASCII .!? 须后随空白/结尾才算句末（避免 3.14、URL 被腰斩）
    private static let cjkEnders: Set<Character> = ["。", "．", "！", "？"]

    /// 在句末标点串（如 ?!、。。）之后切开，紧随的空白吞进前段
    private static func splitAfterSentenceEnds(_ s: Substring) -> [Substring] {
        var parts: [Substring] = []
        var segStart = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            guard sentenceEnders.contains(s[i]) else { i = s.index(after: i); continue }
            var j = i
            var hasCJK = false
            while j < s.endIndex, sentenceEnders.contains(s[j]) {
                if cjkEnders.contains(s[j]) { hasCJK = true }
                j = s.index(after: j)
            }
            if hasCJK || j == s.endIndex || s[j].isWhitespace {
                while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
                parts.append(s[segStart..<j])
                segStart = j
            }
            i = j
        }
        if segStart < s.endIndex { parts.append(s[segStart..<s.endIndex]) }
        return parts
    }

    /// 兜底：按 Character 硬切成 ≤limit 的片段（不破坏扩展字素簇）
    private static func hardCut(_ s: Substring, _ limit: Int) -> [Substring] {
        var parts: [Substring] = []
        var start = s.startIndex
        while start < s.endIndex {
            let end = s.index(start, offsetBy: limit, limitedBy: s.endIndex) ?? s.endIndex
            parts.append(s[start..<end])
            start = end
        }
        return parts
    }
}
