//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
//
//===----------------------------------------------------------------------===//

@unsafe @preconcurrency import XCTest
#if COLLECTIONS_SINGLE_MODULE
import Collections
#else
import _CollectionsTestSupport
import _RopeModule
#endif

/// SplitMix64, so that runs are reproducible across processes.
fileprivate struct SplitMix: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
}

fileprivate struct FuzzRandom {
  var rng: SplitMix
  init(seed: Int) { rng = SplitMix(state: UInt64(truncatingIfNeeded: seed)) }
  mutating func roll(_ n: Int) -> Int {
    precondition(n > 0)
    return Int.random(in: 0 ..< n, using: &rng)
  }
  mutating func chance(_ percent: Int) -> Bool { roll(100) < percent }
}

fileprivate let atoms: [String] = [
  "a", "e", "x", "Z", " ",
  "\u{301}", "\u{308}", "\u{334}", "\u{20DD}",   // combining marks
  "é", "e\u{301}", "ü", "u\u{308}", "Å", "A\u{30A}", "\u{212B}", // canonical pairs
  "\r", "\n", "\r\n",
  "🇺", "🇸", "🇨", "🇦", "🇨🇦",                     // regional indicators
  "👩", "👧", "\u{200D}", "👩‍👩‍👧", "❤", "\u{FE0F}", "\u{1F3FB}", "👍🏽",
  "\u{1100}", "\u{1161}", "\u{11A8}", "가", "각",      // Hangul jamo / syllables
  "क", "\u{94D}", "ष", "\u{93F}",                    // Devanagari + virama
  "\u{600}",                                          // prepend
  "中", "😀", "\u{10FFFF}", "ÿ",
  "\u{E0067}", "\u{E007F}",                           // tags
]

fileprivate func randomString(_ r: inout FuzzRandom, maxAtoms: Int) -> String {
  var s = ""
  let n = r.roll(maxAtoms + 1)
  for _ in 0 ..< n {
    if r.chance(3) {
      // A long run, to produce multiple chunks.
      let atom = atoms[r.roll(atoms.count)]
      s += String(repeating: atom, count: 50 + r.roll(400))
    } else {
      s += atoms[r.roll(atoms.count)]
    }
  }
  return s
}

@available(SwiftStdlib 6.2, *)
fileprivate func charOffsets(_ s: String) -> [Int] {
  var r: [Int] = []
  var i = s.startIndex
  while true {
    r.append(s.utf8.distance(from: s.startIndex, to: i))
    if i == s.endIndex { break }
    i = s.index(after: i)
  }
  return r
}

@available(SwiftStdlib 6.2, *)
fileprivate func scalarOffsets(_ s: String) -> [Int] {
  var r: [Int] = []
  var i = s.startIndex
  while true {
    r.append(s.utf8.distance(from: s.startIndex, to: i))
    if i == s.endIndex { break }
    i = s.unicodeScalars.index(after: i)
  }
  return r
}

@available(SwiftStdlib 6.2, *)
fileprivate func bigCharOffsets(_ b: BigString) -> [Int] {
  var r: [Int] = []
  var i = b.startIndex
  while true {
    r.append(i.utf8Offset)
    if i == b.endIndex { break }
    i = b.index(after: i)
  }
  return r
}

@available(SwiftStdlib 6.2, *)
fileprivate func bigCharOffsetsBackward(_ b: BigString) -> [Int] {
  var r: [Int] = []
  var i = b.endIndex
  while true {
    r.append(i.utf8Offset)
    if i == b.startIndex { break }
    i = b.index(before: i)
  }
  return r.reversed()
}

@available(SwiftStdlib 6.2, *)
fileprivate func bigScalarOffsets(_ b: BigString) -> [Int] {
  var r: [Int] = []
  var i = b.startIndex
  while true {
    r.append(i.utf8Offset)
    if i == b.endIndex { break }
    i = b.unicodeScalars.index(after: i)
  }
  return r
}

fileprivate func esc(_ s: String) -> String {
  if s.utf8.count > 200 {
    return "<\(s.utf8.count) bytes> " + s.debugDescription.prefix(300) + "..."
  }
  return s.unicodeScalars.map { $0.isASCII && $0.value >= 0x20 ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined()
}

@available(SwiftStdlib 6.2, *)
class TestBigStringFuzz: CollectionTestCase {
  override var isAvailable: Bool { isRunningOnSwiftStdlib5_8 }

  /// Returns a list of discrepancies between `big` and `flat`.
  fileprivate func compare(
    _ big: BigString, _ flat: String, random r: inout FuzzRandom
  ) -> [String] {
    var problems: [String] = []
    func check(_ cond: @autoclosure () -> Bool, _ msg: @autoclosure () -> String) {
      if !cond() { problems.append(msg()) }
    }
    big._invariantCheck()
    let s = String(big)
    check(s == flat && s.utf8.elementsEqual(flat.utf8), "contents: \(esc(s)) vs \(esc(flat))")
    check(big.count == flat.count, "count \(big.count) vs \(flat.count)")
    check(big.unicodeScalars.count == flat.unicodeScalars.count, "scalar count")
    check(big.utf8.count == flat.utf8.count, "utf8 count")
    check(big.utf16.count == flat.utf16.count, "utf16 count")
    check(big.isEmpty == flat.isEmpty, "isEmpty")
    check(big.utf8.elementsEqual(flat.utf8), "utf8 elements")
    check(big.utf16.elementsEqual(flat.utf16), "utf16 elements")
    check(big.unicodeScalars.elementsEqual(flat.unicodeScalars), "scalar elements")
    check(Array(big) == Array(flat), "characters: \(Array(big).map { esc(String($0)) }) vs \(Array(flat).map { esc(String($0)) })")
    check(big.reversed().elementsEqual(flat.reversed()), "reversed characters")

    let fc = charOffsets(flat)
    let bc = bigCharOffsets(big)
    check(fc == bc, "char boundaries fwd \(bc) vs \(fc)")
    let bcb = bigCharOffsetsBackward(big)
    check(fc == bcb, "char boundaries bwd \(bcb) vs \(fc)")
    let fs = scalarOffsets(flat)
    check(fs == bigScalarOffsets(big), "scalar boundaries")
    check(big.distance(from: big.startIndex, to: big.endIndex) == flat.count, "distance start-end")

    // Random index conversions.
    let u8 = flat.utf8.count
    for _ in 0 ..< 6 {
      let o = r.roll(u8 + 1)
      let bi = big.utf8.index(big.startIndex, offsetBy: o)
      check(bi.utf8Offset == o, "utf8 offsetBy \(o) -> \(bi.utf8Offset)")
      let down = fc.last(where: { $0 <= o })!
      let up = fc.first(where: { $0 >= o })!
      check(big.index(roundingDown: bi).utf8Offset == down, "char roundingDown \(o): \(big.index(roundingDown: bi).utf8Offset) vs \(down)")
      check(big.index(roundingUp: bi).utf8Offset == up, "char roundingUp \(o): \(big.index(roundingUp: bi).utf8Offset) vs \(up)")
      let sdown = fs.last(where: { $0 <= o })!
      let sup = fs.first(where: { $0 >= o })!
      check(big.unicodeScalars.index(roundingDown: bi).utf8Offset == sdown, "scalar roundingDown \(o)")
      check(big.unicodeScalars.index(roundingUp: bi).utf8Offset == sup, "scalar roundingUp \(o)")

      // Character offsets
      let n = fc.count - 1
      let a = r.roll(n + 1), b = r.roll(n + 1)
      let ia = big.index(big.startIndex, offsetBy: a)
      let ib = big.index(big.startIndex, offsetBy: b)
      check(ia.utf8Offset == fc[a], "index(offsetBy: \(a)) \(ia.utf8Offset) vs \(fc[a])")
      check(big.distance(from: ia, to: ib) == b - a, "distance \(a) \(b): \(big.distance(from: ia, to: ib))")
      check(big.index(ia, offsetBy: b - a).utf8Offset == fc[b], "index(\(a), offsetBy: \(b - a))")
      check(big.index(big.endIndex, offsetBy: a - n).utf8Offset == fc[a], "index(end, offsetBy:)")
      if a < n {
        let fi = flat.index(flat.startIndex, offsetBy: a)
        check(big[ia] == flat[fi], "subscript char \(a)")
      }
      // limitedBy
      let lim = big.index(ia, offsetBy: b - a, limitedBy: ib)
      check(lim?.utf8Offset == fc[b], "limitedBy exact")

      // scalar offsets
      let ns = fs.count - 1
      let sa = r.roll(ns + 1), sb = r.roll(ns + 1)
      let sia = big.unicodeScalars.index(big.startIndex, offsetBy: sa)
      let sib = big.unicodeScalars.index(big.startIndex, offsetBy: sb)
      check(sia.utf8Offset == fs[sa], "scalar index(offsetBy:)")
      check(big.unicodeScalars.distance(from: sia, to: sib) == sb - sa, "scalar distance")

      // utf16
      let n16 = flat.utf16.count
      let ua = r.roll(n16 + 1), ub = r.roll(n16 + 1)
      let uia = big.utf16.index(big.startIndex, offsetBy: ua)
      let uib = big.utf16.index(big.startIndex, offsetBy: ub)
      check(big.utf16.distance(from: uia, to: uib) == ub - ua, "utf16 distance \(ua) \(ub): \(big.utf16.distance(from: uia, to: uib)) uia=\(uia) uib=\(uib)")
      let fua = flat.utf16.index(flat.startIndex, offsetBy: ua)
      check(uia.utf8Offset == flat.utf8.distance(from: flat.startIndex, to: fua) || uia._isUTF16TrailingSurrogate,
            "utf16 index offset \(ua)")
      if ua < n16 {
        check(big.utf16[uia] == flat.utf16[fua], "utf16 subscript \(ua)")
      }
    }

    // Slices.
    if fc.count > 1 {
      let a = r.roll(fc.count), b = r.roll(fc.count)
      let (lo, hi) = (min(a, b), max(a, b))
      let bl = big.index(big.startIndex, offsetBy: lo)
      let bh = big.index(big.startIndex, offsetBy: hi)
      let fl = flat.index(flat.startIndex, offsetBy: lo)
      let fh = flat.index(flat.startIndex, offsetBy: hi)
      let bs = big[bl ..< bh]
      let fsub = flat[fl ..< fh]
      check(String(bs) == String(fsub), "slice contents")
      check(bs.count == fsub.count, "slice count \(bs.count) vs \(fsub.count)")
      check(Array(bs) == Array(fsub), "slice chars")
      check(bs.utf8.count == fsub.utf8.count, "slice utf8 count")
      check(bs.utf16.count == fsub.utf16.count, "slice utf16 count")
      check(bs.unicodeScalars.count == fsub.unicodeScalars.count, "slice scalar count")
      check(bs.reversed().elementsEqual(fsub.reversed()), "slice reversed")
      let copy = BigString(bs)
      copy._invariantCheck()
      check(String(copy) == String(fsub), "BigString(slice)")
      check(copy.count == fsub.count, "BigString(slice).count \(copy.count) vs \(fsub.count)")
      check(Array(copy) == Array(String(fsub)), "BigString(slice) chars")
    }

    // Equality, hashing and ordering against a canonically-equivalent variant.
    let variant = flat
      .replacingOccurrences(of: "é", with: "e\u{301}")
      .replacingOccurrences(of: "Å", with: "\u{212B}")
    let bv = BigString(variant)
    check((big == bv) == (flat == variant), "== canonical variant: \(big == bv) vs \(flat == variant)")
    if flat == variant {
      check(big.hashValue == bv.hashValue, "hash of canonical variant")
    }
    return problems
  }

  fileprivate func runFuzz(seed: Int, steps: Int) -> Bool {
    var r = FuzzRandom(seed: seed)
    var flat = randomString(&r, maxAtoms: 30)
    var big = BigString(flat)
    var log: [String] = ["init(\(esc(flat)))"]
    var snapshots: [(BigString, String)] = []

    func charIndex(_ k: Int) -> (BigString.Index, String.Index) {
      (big.index(big.startIndex, offsetBy: k), flat.index(flat.startIndex, offsetBy: k))
    }
    func scalarIndex(_ k: Int) -> (BigString.Index, String.Index) {
      (big.unicodeScalars.index(big.startIndex, offsetBy: k),
       flat.unicodeScalars.index(flat.startIndex, offsetBy: k))
    }
    func charRange() -> (Range<BigString.Index>, Range<String.Index>, String) {
      let n = flat.count
      let a = r.roll(n + 1), b = r.roll(n + 1)
      let (lo, hi) = (min(a, b), max(a, b))
      let (bl, fl) = charIndex(lo)
      let (bh, fh) = charIndex(hi)
      return (bl ..< bh, fl ..< fh, "chars \(lo)..<\(hi)")
    }
    func scalarRange() -> (Range<BigString.Index>, Range<String.Index>, String) {
      let n = flat.unicodeScalars.count
      let a = r.roll(n + 1), b = r.roll(n + 1)
      let (lo, hi) = (min(a, b), max(a, b))
      let (bl, fl) = scalarIndex(lo)
      let (bh, fh) = scalarIndex(hi)
      return (bl ..< bh, fl ..< fh, "scalars \(lo)..<\(hi)")
    }

    for step in 0 ..< steps {
      let op = r.roll(18)
      switch op {
      case 0:
        let (br, fr, d) = charRange()
        let s = randomString(&r, maxAtoms: 6)
        log.append("replaceSubrange(\(d), with: \(esc(s)))")
        big.replaceSubrange(br, with: s)
        flat.replaceSubrange(fr, with: s)
      case 1:
        let k = r.roll(flat.count + 1)
        let s = randomString(&r, maxAtoms: 6)
        log.append("insert(contentsOf: \(esc(s)), atChar: \(k))")
        let (bi, fi) = charIndex(k)
        big.insert(contentsOf: s, at: bi)
        flat.insert(contentsOf: s, at: fi)
      case 2:
        let s = randomString(&r, maxAtoms: 6)
        log.append("append(contentsOf: \(esc(s)))")
        big.append(contentsOf: s)
        flat.append(contentsOf: s)
      case 3:
        let (br, fr, d) = charRange()
        log.append("removeSubrange(\(d))")
        big.removeSubrange(br)
        flat.removeSubrange(fr)
      case 4:
        let (br, fr, d) = scalarRange()
        let s = randomString(&r, maxAtoms: 4)
        log.append("unicodeScalars.replaceSubrange(\(d), with: \(esc(s)))")
        big.unicodeScalars.replaceSubrange(br, with: s.unicodeScalars)
        flat.unicodeScalars.replaceSubrange(fr, with: s.unicodeScalars)
      case 5:
        let k = r.roll(flat.unicodeScalars.count + 1)
        let s = randomString(&r, maxAtoms: 3)
        log.append("unicodeScalars.insert(contentsOf: \(esc(s)), atScalar: \(k))")
        let (bi, fi) = scalarIndex(k)
        big.unicodeScalars.insert(contentsOf: s.unicodeScalars, at: bi)
        flat.unicodeScalars.insert(contentsOf: s.unicodeScalars, at: fi)
      case 6:
        guard !flat.isEmpty else { continue }
        let k = r.roll(flat.unicodeScalars.count)
        log.append("unicodeScalars.remove(atScalar: \(k))")
        let (bi, fi) = scalarIndex(k)
        let a = big.unicodeScalars.remove(at: bi)
        let b = flat.unicodeScalars.remove(at: fi)
        if a != b { log.append("!! removed scalar \(a) vs \(b)") }
      case 7:
        guard !flat.isEmpty else { continue }
        let k = r.roll(flat.count)
        log.append("remove(atChar: \(k))")
        let (bi, fi) = charIndex(k)
        let a = big.remove(at: bi)
        let b = flat.remove(at: fi)
        if a != b { log.append("!! removed char \(esc(String(a))) vs \(esc(String(b)))") }
      case 8:
        // insert(contentsOf:) a slice of self
        let (br, fr, d) = charRange()
        let k = r.roll(flat.count + 1)
        log.append("insert(contentsOf: self[\(d)], atChar: \(k))")
        let (bi, fi) = charIndex(k)
        let bs = big[br]
        let fs = flat[fr]
        big.insert(contentsOf: bs, at: bi)
        flat.insert(contentsOf: fs, at: fi)
      case 9:
        // replaceSubrange with slice of self
        let (sr, sfr, sd) = charRange()
        let (tr, tfr, td) = charRange()
        log.append("replaceSubrange(\(td), with: self[\(sd)])")
        let bs = big[sr]
        let fs = String(flat[sfr])
        big.replaceSubrange(tr, with: bs)
        flat.replaceSubrange(tfr, with: fs)
      case 10:
        // replace with a whole other BigString
        let (tr, tfr, td) = charRange()
        let s = randomString(&r, maxAtoms: 20)
        log.append("replaceSubrange(\(td), with: BigString(\(esc(s))))")
        big.replaceSubrange(tr, with: BigString(s))
        flat.replaceSubrange(tfr, with: s)
      case 11:
        // Split and rejoin at a scalar boundary.
        let k = r.roll(flat.unicodeScalars.count + 1)
        log.append("split/rejoin atScalar: \(k)")
        let (bi, fi) = scalarIndex(k)
        var a = BigString(big.unicodeScalars[..<bi])
        let b = BigString(big.unicodeScalars[bi...])
        a._invariantCheck(); b._invariantCheck()
        let fa = String(flat.unicodeScalars[..<fi])
        let fb = String(flat.unicodeScalars[fi...])
        if a.count != fa.count || b.count != fb.count {
          log.append("!! split counts \(a.count),\(b.count) vs \(fa.count),\(fb.count)")
        }
        a.append(contentsOf: b)
        big = a
      case 12:
        // BigSubstring mutation, check base
        let (br, fr, d) = charRange()
        var bs = big[br]
        var fs = flat[fr]
        let n = fs.count
        let x = r.roll(n + 1), y = r.roll(n + 1)
        let (lo, hi) = (min(x, y), max(x, y))
        let s = randomString(&r, maxAtoms: 3)
        log.append("var sub = self[\(d)]; sub.replaceSubrange(\(lo)..<\(hi), with: \(esc(s)))")
        let bl = bs.index(bs.startIndex, offsetBy: lo)
        let bh = bs.index(bs.startIndex, offsetBy: hi)
        let fl = fs.index(fs.startIndex, offsetBy: lo)
        let fh = fs.index(fs.startIndex, offsetBy: hi)
        let oldU8 = flat.utf8.count
        let startOff = br.lowerBound.utf8Offset
        let endOff = br.upperBound.utf8Offset
        bs.replaceSubrange(bl ..< bh, with: s)
        fs.replaceSubrange(fl ..< fh, with: s)
        flat = String(fs.base)
        big = bs.base
        // BigSubstring rounds its bounds down to Character boundaries after mutation.
        let co = charOffsets(flat)
        let delta = flat.utf8.count - oldU8
        let eLo = co.last(where: { $0 <= startOff })!
        let eHi = co.last(where: { $0 <= endOff + delta })!
        let u = Array(flat.utf8)
        let expected = String(decoding: u[eLo ..< eHi], as: UTF8.self)
        if String(bs) != expected || bs.count != expected.count {
          log.append("!! substring after mutation: \(esc(String(bs))) (\(bs.count)) vs \(esc(expected)) (\(expected.count))")
        }
      case 13:
        // BigSubstring unicodeScalars mutation
        let (br, fr, d) = scalarRange()
        var bs = big.unicodeScalars[br]
        var fs = flat.unicodeScalars[fr]
        let s = randomString(&r, maxAtoms: 2)
        let atEnd = r.chance(50)
        log.append("var sub = self.unicodeScalars[\(d)]; sub.\(atEnd ? "append" : "insert at start")(contentsOf: \(esc(s)))")
        if atEnd {
          bs.append(contentsOf: s.unicodeScalars)
          fs.append(contentsOf: s.unicodeScalars)
        } else {
          bs.insert(contentsOf: s.unicodeScalars, at: bs.startIndex)
          fs.insert(contentsOf: s.unicodeScalars, at: fs.startIndex)
        }
        if String(String.UnicodeScalarView(bs)) != String(fs) {
          log.append("!! scalar substring after mutation: \(esc(String(String.UnicodeScalarView(bs))))) vs \(esc(String(fs)))")
        }
        big = BigString(bs.base)
        flat = String(flat.unicodeScalars[..<fr.lowerBound]) + String(fs) + String(flat.unicodeScalars[fr.upperBound...])
      case 14:
        // Snapshot for COW
        snapshots.append((big, flat))
        if snapshots.count > 4 { snapshots.removeFirst() }
        log.append("snapshot")
      case 15:
        // Append single characters
        let s = randomString(&r, maxAtoms: 3)
        log.append("append chars of \(esc(s))")
        for c in s { big.append(c) }
        flat.append(contentsOf: s)
      case 16:
        // Insert character
        let k = r.roll(flat.count + 1)
        let s = atoms[r.roll(atoms.count)]
        guard s.count == 1 else { continue }
        let c = Character(s)
        log.append("insert(\(esc(s)), atChar: \(k))")
        let (bi, fi) = charIndex(k)
        big.insert(c, at: bi)
        flat.insert(c, at: fi)
      case 17:
        // Restore from snapshot (also exercises shared storage)
        guard let snap = snapshots.randomElement(using: &r.rng) else { continue }
        log.append("restore snapshot")
        (big, flat) = snap
      default:
        fatalError()
      }

      var problems = log.last!.hasPrefix("!!") ? [log.last!] : []
      problems += compare(big, flat, random: &r)
      for (i, (sb, sf)) in snapshots.enumerated() {
        if String(sb) != sf { problems.append("snapshot \(i) changed") }
      }
      if !problems.isEmpty {
        print("FUZZ FAILURE seed \(seed) step \(step)")
        for l in log { print("  op: \(l)") }
        for p in problems.prefix(10) { print("  problem: \(p)") }
        XCTFail("seed \(seed) step \(step): \(problems.first!)")
        return false
      }
    }
    return true
  }

  func test_fuzz() {
    let base = Int(ProcessInfo.processInfo.environment["FUZZ_SEED"] ?? "0") ?? 0
    let count = Int(ProcessInfo.processInfo.environment["FUZZ_COUNT"] ?? "200") ?? 200
    let steps = Int(ProcessInfo.processInfo.environment["FUZZ_STEPS"] ?? "40") ?? 40
    var failures = 0
    for seed in base ..< base + count {
      if !runFuzz(seed: seed, steps: steps) {
        failures += 1
        if failures >= 3 { break }
      }
    }
  }

  func test_utf16_distance() {
    var r = FuzzRandom(seed: 1)
    var failures = 0
    for _ in 0 ..< 200 {
      let flat = randomString(&r, maxAtoms: 30)
      let big = BigString(flat)
      let n = flat.utf16.count
      for _ in 0 ..< 50 {
        let a = r.roll(n + 1), b = r.roll(n + 1)
        let ia = big.utf16.index(big.startIndex, offsetBy: a)
        let ib = big.utf16.index(big.startIndex, offsetBy: b)
        let d = big.utf16.distance(from: ia, to: ib)
        if d != b - a {
          failures += 1
          if failures < 10 {
            print("UTF16 DIST: \(esc(flat)) a=\(a) b=\(b) got \(d) ia=\(ia) ib=\(ib)")
          }
        }
      }
    }
    expectEqual(failures, 0)
  }

  func test_ordering_fuzz() {
    // Compare BigString ordering against String ordering.
    var r = FuzzRandom(seed: 0)
    var failures = 0
    for _ in 0 ..< 3000 {
      let a = randomString(&r, maxAtoms: 4)
      let b = randomString(&r, maxAtoms: 4)
      let ba = BigString(a), bb = BigString(b)
      if (ba < bb) != (a < b) || (ba == bb) != (a == b) {
        print("ORDER MISMATCH: \(esc(a)) vs \(esc(b)): big < \(ba < bb), == \(ba == bb); string < \(a < b), == \(a == b)")
        failures += 1
        if failures > 10 { break }
      }
    }
    expectEqual(failures, 0)
  }
}
