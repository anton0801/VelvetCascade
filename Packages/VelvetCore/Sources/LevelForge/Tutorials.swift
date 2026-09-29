// Tutorials.swift — обучающие подсказки (английский UI-текст) и «New: …» механики уровней.

import VelvetDomain

enum Tutorials {
    /// (название для Level Brief, тема Handbook)
    static func newMechanic(for id: Int) -> (String, String)? {
        switch id {
        case 1: return ("Matches", "matches")
        case 3: return ("Stage Turn", "stageTurn")
        case 4: return ("LineSpark", "specials")
        case 5: return ("Curtain Sweep", "curtainSweep")
        case 7: return ("Stage Burst", "specials")
        case 8: return ("Prism", "specials")
        case 11: return ("Velvet Plates", "velvetPlates")
        case 15: return ("Double Stitch", "velvetPlates")
        case 21: return ("Keys & Exits", "keysExits")
        case 26: return ("Two Turns", "stageTurn")
        case 41: return ("Crates", "crates")
        case 44: return ("Sturdy Crates", "crates")
        case 53: return ("Brass Baffles", "curtainSweep")
        case 61: return ("Ice", "ice")
        case 64: return ("Thick Ice", "ice")
        case 81: return ("Chains", "chains")
        case 101: return ("Shutters & Switches", "shutters")
        case 108: return ("Switch Sequence", "shutters")
        case 121: return ("Split Stage", "curtainSweep")
        case 141: return ("Inner Exits", "keysExits")
        case 152: return ("Left Exit", "keysExits")
        default: return nil
        }
    }

    static func steps(for id: Int) -> [TutorialStep] {
        func s(_ trigger: String, _ title: String, _ text: String) -> TutorialStep {
            TutorialStep(trigger: trigger, title: title, text: text)
        }
        switch id {
        case 1:
            return [s("start", "Make a match", "Swap two neighbouring gems to line up three Hearts.")]
        case 2:
            return [s("start", "Choose your cue", "More than one swap works. Pick the one that gathers Diamonds.")]
        case 3:
            return [s("start", "Your first Turn", "The Stage Charge is full. Tap Turn Stage to preview the quarter turn — the preview is free."),
                    s("afterTurn", "The stage turned", "Pieces still fall toward the floor. The edge that reached the floor was swept clear.")]
        case 4:
            return [s("start", "Four in a row", "Match four gems in a line to create a LineSpark. It clears its whole row or column.")]
        case 5:
            return [s("start", "First cascade", "A Turn sweeps the new bottom edge. Falling gems can start a second wave.")]
        case 6:
            return [s("start", "Earn the Turn", "Charge starts at 6 of 12. Matches of three add 1, four add 3, five add 5."),
                    s("chargeFull", "Charge is full", "Preview the Turn before you commit — it costs one move.")]
        case 7:
            return [s("start", "Crossed lights", "Match five gems in a T or L shape to create a Stage Burst.")]
        case 8:
            return [s("start", "Prism rehearsal", "Line up five in a row for a Prism. Swap it with a gem to clear every gem of that colour.")]
        case 11:
            return [s("start", "Velvet Plates", "Plates lift when a gem standing on them is cleared. Falling onto a plate does not count.")]
        case 15:
            return [s("start", "Double stitch", "Plates with two studs need two clears in that cell.")]
        case 21:
            return [s("start", "The first key", "Keys can't be swapped. An exit works only when its arrow points to the floor."),
                    s("chargeFull", "Face the exit down", "Turn the stage so the exit arrow points down, then clear the gems in the key's way.")]
        case 22:
            return [s("start", "A door below", "This exit already faces the floor. Clear the gems beneath the key.")]
        case 26:
            return [s("start", "Opposite door", "An Up exit needs two clockwise turns. Recharge the stage between them.")]
        case 41:
            return [s("start", "Stage props", "Crates can't move. A match next to a crate, or a blast, knocks off one layer.")]
        case 44:
            return [s("start", "Sturdy crates", "Crates with two studs take two hits — at most one hit per wave.")]
        case 53:
            return [s("start", "Brass baffles", "Baffles never break. They split the stage into separate falls, each with its own inlet.")]
        case 61:
            return [s("start", "A thin frost", "Ice pins a gem in place. Match that gem, or blast it, to crack the ice.")]
        case 64:
            return [s("start", "A second layer", "Thick ice needs two hits. The gem stays put until the ice is gone.")]
        case 81:
            return [s("start", "The first chain", "A chain pins its gem like ice but breaks with a single hit.")]
        case 101:
            return [s("start", "A hidden door", "Clear the gem on a switch to open its matching shutters for good.")]
        case 108:
            return [s("start", "Two acts", "Switch A opens the way to switch B. Follow the letters.")]
        case 121:
            return [s("start", "Two little stages", "Each pavilion refills from its own inlet. Pieces never pass through walls.")]
        case 141:
            return [s("start", "The inner balcony", "Exits can face the empty centre of the ring.")]
        case 152:
            return [s("start", "The far balcony", "A Left exit needs three clockwise turns. Plan your charge.")]
        default:
            return []
        }
    }
}
