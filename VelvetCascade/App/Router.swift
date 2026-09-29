// Router.swift — iOS 15-совместимый координатор 22 маршрутов (без NavigationStack).

import SwiftUI

enum HandbookTopic: String, CaseIterable, Identifiable {
    case matches, stageTurn, curtainSweep, keysExits, velvetPlates, crates, ice, chains, shutters, specials, dailyEncore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matches: return "Matches"
        case .stageTurn: return "Stage Turn"
        case .curtainSweep: return "Curtain Sweep"
        case .keysExits: return "Keys & Exits"
        case .velvetPlates: return "Velvet Plates"
        case .crates: return "Crates"
        case .ice: return "Ice"
        case .chains: return "Chains"
        case .shutters: return "Shutters"
        case .specials: return "Specials"
        case .dailyEncore: return "Daily Encore"
        }
    }
}

/// Маршруты спецификации (Screen/Route). Номера — порядок экранов 01–22.
enum Route: Hashable {
    case welcome                          // 01 onboarding/welcome
    case matchTutorial                    // 02 onboarding/match
    case rotationTutorial                 // 03 onboarding/rotate
    case home                             // 04 home
    case worlds                           // 05 worlds
    case worldMap(world: Int)             // 06 worlds/:worldID
    case levelBrief(level: Int)           // 07 levels/:levelID/brief
    case gameplay(runID: String)          // 08 game/:runID (09 turn-preview, 10 pause — состояния внутри)
    case curtainCall(runID: String)       // 11 results/win/:runID
    case oneMoreAct(runID: String)        // 12 results/fail/:runID
    case newTheatre(world: Int, final: Bool) // 13 worlds/unlocked/:worldID
    case daily                            // 14 daily
    case dailyReward(receiptID: String)   // 15 daily/reward/:receiptID
    case handbook(topic: HandbookTopic?)  // 16 help
    case settings                         // 17 settings
    case credits                          // 18 settings/credits
    case importReview                     // 19 settings/import/review
    #if DEBUG
    case gallery(page: Int)               // DEBUG: превью компонентов UI01–UI20
    #endif
}

/// Модальные состояния поверх маршрута.
enum ModalRoute: Hashable {
    case recovery                         // 20 shared/error
    case dailyRules                       // 21 daily/rules
    case resetConfirm                     // 22 settings/reset
    case replaceRun(level: Int)           // Replace Active Run
}

@MainActor
final class Router: ObservableObject {
    @Published private(set) var stack: [Route]
    @Published var modal: ModalRoute?
    @Published var transitionForward = true

    init(root: Route) {
        stack = [root]
    }

    var current: Route { stack.last ?? .home }

    func push(_ r: Route) {
        transitionForward = true
        withAnimation(.easeInOut(duration: 0.28)) { stack.append(r) }
    }

    func pop() {
        guard stack.count > 1 else { return }
        transitionForward = false
        withAnimation(.easeInOut(duration: 0.28)) { _ = stack.popLast() }
    }

    /// Вернуться к ближайшему маршруту, удовлетворяющему условию (или заменить стек).
    func popTo(_ predicate: (Route) -> Bool, orReset fallback: [Route]) {
        transitionForward = false
        withAnimation(.easeInOut(duration: 0.28)) {
            if let i = stack.lastIndex(where: predicate) {
                stack = Array(stack[...i])
            } else {
                stack = fallback
            }
        }
    }

    func reset(_ routes: [Route], forward: Bool = true) {
        transitionForward = forward
        withAnimation(.easeInOut(duration: 0.3)) { stack = routes }
    }

    func replaceTop(_ r: Route) {
        transitionForward = true
        withAnimation(.easeInOut(duration: 0.28)) {
            _ = stack.popLast()
            stack.append(r)
        }
    }

    func goHome() {
        popTo({ $0 == .home }, orReset: [.home])
    }

    func goWorldMap(_ world: Int) {
        popTo({ if case .worldMap(let w) = $0 { return w == world }; return false },
              orReset: [.home, .worlds, .worldMap(world: world)])
    }
}
