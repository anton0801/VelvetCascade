// HintPolicy.swift — одно допустимое действие для подсказки.
//
// Приоритет: действие с немедленным прогрессом цели → создание special → любой valid swap;
// если swap нет и доступен Turn — Turn. Нет legal action — нет подсказки (и нет списания ticket).
// Подсказка не выполняет swap и не расходует RNG попытки: симуляция идёт на копии.

public enum HintSuggestion: Hashable, Sendable {
    case swap(from: Coord, to: Coord)
    case turn
}

public enum HintPolicy {
    /// Немедленный прогресс целей между двумя состояниями (0 — нет прогресса).
    public static func objectiveProgress(before: GameState, after: GameState) -> Int {
        var p = 0
        for obj in before.objectives {
            switch obj {
            case .collect(let color, _):
                let rem = before.remaining(for: obj)
                p += min(rem, after.collected[color.rawValue] - before.collected[color.rawValue])
            case .plates:
                p += max(0, before.board.remainingPlateHP - after.board.remainingPlateHP)
            case .keys:
                p += 10 * max(0, after.extractedKeyIDs.count - before.extractedKeyIDs.count)
            }
        }
        return p
    }

    public static func suggest(for state: GameState) -> HintSuggestion? {
        guard state.status == .playing, state.movesLeft > 0 else { return nil }
        let swaps = GameEngine.validSwaps(state)
        var bestProgress = 0
        var best: HintSuggestion?
        var firstSpecial: HintSuggestion?

        if state.isTurnAvailable,
           let r = try? GameEngine.apply(GameAction(id: "hint-sim-turn", kind: .rotate), to: state, recordSteps: false) {
            let p = objectiveProgress(before: state, after: r.state)
            if p > bestProgress { bestProgress = p; best = .turn }
        }
        for sw in swaps {
            let action = GameAction(id: "hint-sim-\(sw.from.x)-\(sw.from.y)-\(sw.to.x)-\(sw.to.y)",
                                    kind: .swap(from: sw.from, to: sw.to))
            guard let r = try? GameEngine.apply(action, to: state, recordSteps: false) else { continue }
            let p = objectiveProgress(before: state, after: r.state)
            if p > bestProgress { bestProgress = p; best = .swap(from: sw.from, to: sw.to) }
            if firstSpecial == nil && r.state.specialsCreated > state.specialsCreated {
                firstSpecial = .swap(from: sw.from, to: sw.to)
            }
        }
        if let best { return best }
        if let firstSpecial { return firstSpecial }
        if let first = swaps.first { return .swap(from: first.from, to: first.to) }
        return state.isTurnAvailable ? .turn : nil
    }
}
