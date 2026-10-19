import Foundation

/// Line-level diff and three-way merge built on the standard library's Myers implementation.
public enum LineDiff {
    public struct Result {
        /// 0-based line indices in `new` that were inserted or replaced.
        public var changedNewLines: Set<Int>
        /// 0-based line indices in `new` *before which* lines from `old` were removed (index == new.count means at end).
        public var removedBefore: Set<Int>
        /// Maps an old line index to the new line index when the line survived unchanged.
        public var oldToNew: [Int: Int]
    }

    public static func lines(_ s: String) -> [Substring] {
        var out = s.split(separator: "\n", omittingEmptySubsequences: false)
        if out.last == "" , s.hasSuffix("\n") { out.removeLast() }
        return out
    }

    public static func diff(old: String, new: String) -> Result {
        let a = lines(old), b = lines(new)
        let d = b.difference(from: a)
        var removedOld = Set<Int>(), insertedNew = Set<Int>()
        for c in d {
            switch c {
            case .remove(let off, _, _): removedOld.insert(off)
            case .insert(let off, _, _): insertedNew.insert(off)
            }
        }
        // Walk both sides to build the survivor map and locate removals in new coordinates.
        var oldToNew: [Int: Int] = [:]
        var removedBefore = Set<Int>()
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removedOld.contains(i) {
                // removal; find where it lands in new: the next surviving new index
                var k = j
                while k < b.count, insertedNew.contains(k) { k += 1 }
                removedBefore.insert(k)
                i += 1
            } else if j < b.count, insertedNew.contains(j) {
                j += 1
            } else if i < a.count, j < b.count {
                oldToNew[i] = j
                i += 1; j += 1
            } else { break }
        }
        return Result(changedNewLines: insertedNew, removedBefore: removedBefore, oldToNew: oldToNew)
    }

    /// Nearest surviving new line at or before `oldLine`, else at or after, else 0.
    public static func mapLine(_ oldLine: Int, _ r: Result, oldCount: Int) -> Int {
        if let n = r.oldToNew[oldLine] { return n }
        var k = oldLine - 1
        while k >= 0 { if let n = r.oldToNew[k] { return n + 1 }; k -= 1 }
        k = oldLine + 1
        while k < oldCount { if let n = r.oldToNew[k] { return n }; k += 1 }
        return 0
    }
}

public enum ThreeWayMerge {
    public struct Outcome: Equatable {
        public var text: String
        /// 0-based line indices in `text` that were kept from `ours` despite a conflicting change in `theirs`.
        public var conflictLines: [Int]
        public var hadConflict: Bool { !conflictLines.isEmpty }
    }

    /// Line-level merge. Non-overlapping hunks apply from both sides; overlapping hunks keep ours.
    public static func merge(base: String, ours: String, theirs: String) -> Outcome {
        if ours == base { return Outcome(text: theirs, conflictLines: []) }
        if theirs == base { return Outcome(text: ours, conflictLines: []) }
        if ours == theirs { return Outcome(text: ours, conflictLines: []) }
        let b = LineDiff.lines(base), o = LineDiff.lines(ours), t = LineDiff.lines(theirs)
        let ho = hunks(base: b, other: o), ht = hunks(base: b, other: t)
        var out: [Substring] = []
        var conflicts: [Int] = []
        var i = 0            // base index
        var io = 0, it = 0   // hunk cursors
        while i <= b.count {
            let nextO = io < ho.count ? ho[io] : nil
            let nextT = it < ht.count ? ht[it] : nil
            let startO = nextO?.baseStart ?? Int.max, startT = nextT?.baseStart ?? Int.max
            if startO == Int.max && startT == Int.max {
                if i < b.count { out.append(contentsOf: b[i...]) }
                break
            }
            let next = min(startO, startT)
            if next > i { out.append(contentsOf: b[i..<next]); i = next }
            // collect all hunks from both sides that overlap starting at i
            var endBase = i
            var oh: [Hunk] = [], th: [Hunk] = []
            var progressed = true
            while progressed {
                progressed = false
                while io < ho.count, ho[io].baseStart <= endBase, ho[io].baseStart >= i || ho[io].baseEnd > i {
                    oh.append(ho[io]); endBase = max(endBase, ho[io].baseEnd); io += 1; progressed = true
                }
                while it < ht.count, ht[it].baseStart <= endBase, ht[it].baseStart >= i || ht[it].baseEnd > i {
                    th.append(ht[it]); endBase = max(endBase, ht[it].baseEnd); it += 1; progressed = true
                }
            }
            if oh.isEmpty, th.isEmpty { break }
            let region = i..<max(endBase, i)
            if th.isEmpty {
                out.append(contentsOf: replacement(for: region, hunks: oh, base: b, other: o))
            } else if oh.isEmpty {
                out.append(contentsOf: replacement(for: region, hunks: th, base: b, other: t))
            } else {
                let ourLines = replacement(for: region, hunks: oh, base: b, other: o)
                let theirLines = replacement(for: region, hunks: th, base: b, other: t)
                if ourLines == theirLines {
                    out.append(contentsOf: ourLines)
                } else {
                    let start = out.count
                    out.append(contentsOf: ourLines)
                    conflicts.append(contentsOf: start..<max(start + 1, out.count))
                }
            }
            i = max(endBase, i)
            if region.isEmpty && oh.allSatisfy({ $0.baseEnd == $0.baseStart }) && th.allSatisfy({ $0.baseEnd == $0.baseStart }) {
                // pure insertions at i: continue with base line i itself
                if i < b.count { out.append(b[i]); i += 1 }
            }
        }
        var text = out.joined(separator: "\n")
        if (ours.hasSuffix("\n") || theirs.hasSuffix("\n")) && !text.isEmpty { text += "\n" }
        return Outcome(text: text, conflictLines: conflicts)
    }

    struct Hunk { var baseStart: Int; var baseEnd: Int; var otherStart: Int; var otherEnd: Int }

    /// Contiguous change regions between base and other, in base coordinates.
    static func hunks(base: [Substring], other: [Substring]) -> [Hunk] {
        let d = other.difference(from: base)
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in d { switch c { case .remove(let o, _, _): removed.insert(o); case .insert(let o, _, _): inserted.insert(o) } }
        var hunks: [Hunk] = []
        var i = 0, j = 0
        while i < base.count || j < other.count {
            if (i < base.count && removed.contains(i)) || (j < other.count && inserted.contains(j)) {
                let bs = i, os = j
                while i < base.count, removed.contains(i) { i += 1 }
                while j < other.count, inserted.contains(j) { j += 1 }
                hunks.append(Hunk(baseStart: bs, baseEnd: i, otherStart: os, otherEnd: j))
            } else {
                i += 1; j += 1
            }
        }
        return hunks
    }

    static func replacement(for region: Range<Int>, hunks: [Hunk], base: [Substring], other: [Substring]) -> [Substring] {
        // Map the base region to the other side's range covering the same span.
        guard let first = hunks.first, let last = hunks.last else { return Array(base[region]) }
        let leadBase = region.lowerBound..<first.baseStart
        let trailBase = last.baseEnd..<region.upperBound
        let otherLo = first.otherStart - leadBase.count
        let otherHi = last.otherEnd + trailBase.count
        return Array(other[max(0, otherLo)..<min(other.count, otherHi)])
    }
}
