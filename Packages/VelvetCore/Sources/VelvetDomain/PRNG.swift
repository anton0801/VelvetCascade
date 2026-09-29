// PRNG.swift — детерминированный генератор попытки уровня.
//
// rngAlgorithmVersion = 1: SplitMix64 (Steele, Lea, Flood 2014). Состояние — один UInt64,
// хранится в ActiveRun. Одинаковые levelVersion, seed и actions дают одинаковый board.
// Для Daily Encore этот генератор НЕ используется (там системный криптографический источник).

public struct LevelRNG: Hashable, Codable, Sendable {
    public static let algorithmVersion = 1

    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Равномерное целое в 0..<bound без modulo bias (Lemire, с отбрасыванием).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        var m = next().multipliedFullWidth(by: b)
        if m.low < b {
            let threshold = (0 &- b) % b
            while m.low < threshold {
                m = next().multipliedFullWidth(by: b)
            }
        }
        return Int(m.high)
    }

    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = nextInt(below: i + 1)
            if i != j { array.swapAt(i, j) }
        }
    }
}
