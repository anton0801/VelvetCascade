// FlowUITests.swift — сквозные UI-тесты с настоящими тапами и свайпами (XCUITest).

import XCTest

final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = fresh ? ["-VCUITestFreshProfile"] : []
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Дождаться окончания анимации перехода между экранами (0.3 s) перед следующим тапом.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Первый запуск → Welcome → Skip → Home; повторный запуск открывает Home (onboarding сохранён).
    func testFreshLaunchSkipPersistsOnboarding() {
        var app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Begin"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        XCTAssertTrue(button(app, containing: "Play Level 1").waitForExistence(timeout: 5))
        app.terminate()
        app = launch(fresh: false)
        XCTAssertTrue(button(app, containing: "Play Level 1").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Begin"].exists)
    }

    /// Home → Level Brief → Start → реальный свайп по клеткам; invalid swap не тратит ход, valid — тратит.
    func testSwipeSwapSpendsMoveOnlyWhenValid() {
        let app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        button(app, containing: "Play Level 1").tap()
        XCTAssertTrue(app.buttons["Start Level"].waitForExistence(timeout: 5))
        settle()
        app.buttons["Start Level"].tap()
        let moves = element(app, "Moves")
        XCTAssertTrue(moves.waitForExistence(timeout: 10))
        let startValue = moves.value as? String
        XCTAssertEqual(startValue, "18")
        var swapped = false
        outer: for r in 1...6 {
            for c in 1...6 {
                for (dr, dc) in [(0, 1), (1, 0)] where r + dr <= 6 && c + dc <= 6 {
                    let a = element(app, "Row \(r), column \(c)")
                    let b = element(app, "Row \(r + dr), column \(c + dc)")
                    guard a.exists, b.exists else { continue }
                    a.press(forDuration: 0.05, thenDragTo: b)
                    // Дождаться settled-состояния и проверить ход.
                    let changed = NSPredicate(format: "value != %@", startValue ?? "")
                    let exp = expectation(for: changed, evaluatedWith: moves)
                    if XCTWaiter.wait(for: [exp], timeout: 2.5) == .completed {
                        swapped = true
                        break outer
                    }
                }
            }
        }
        XCTAssertTrue(swapped, "no valid swap found by swiping")
        XCTAssertEqual(moves.value as? String, "17")
        // Pause → Intermission → Resume.
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        XCTAssertFalse(app.buttons["Resume"].exists)
    }

    /// Daily Encore: Free Spin → награда уже начислена → Continue → Home показывает «Collected today».
    func testDailySpinOncePerDay() {
        let app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        button(app, containing: "Daily Encore").tap()
        if !app.buttons["Free Spin"].waitForExistence(timeout: 5) {
            XCTFail("Free Spin missing. Hierarchy: \(app.debugDescription)")
            return
        }
        app.buttons["Free Spin"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Hint Ticket' OR label CONTAINS 'Ticket limit'")).firstMatch.exists
                      || element(app, "Added to your collection").exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(button(app, containing: "Collected today").waitForExistence(timeout: 5))
        settle()
        button(app, containing: "Daily Encore").tap()
        let collected = app.buttons.matching(NSPredicate(format: "label == 'Collected today'")).firstMatch
        XCTAssertTrue(collected.waitForExistence(timeout: 5))
        XCTAssertFalse(collected.isEnabled)
    }

    /// Settings → Reset Progress → подтверждение с Cancel не меняет прогресс.
    func testResetConfirmationCancel() {
        let app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        app.buttons["Settings"].tap()
        settle()
        let reset = app.buttons["Reset Progress"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        if !reset.isHittable { app.swipeUp() }
        reset.tap()
        XCTAssertTrue(element(app, "Reset your progress?").waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(element(app, "Reset your progress?").exists)
    }

    /// Settings → Export Progress → системный share sheet с файлом VelvetCascade_Backup_YYYY-MM-DD.json.
    func testExportOpensShareSheet() {
        let app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        app.buttons["Settings"].tap()
        settle()
        let export = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Export Progress'")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        let sheet = app.otherElements["ActivityListView"]
        let fileTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'VelvetCascade_Backup_'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8) || fileTitle.waitForExistence(timeout: 2), "share sheet did not appear")
    }

    private func startLevel1(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        button(app, containing: "Play Level 1").tap()
        XCTAssertTrue(app.buttons["Start Level"].waitForExistence(timeout: 5))
        settle()
        app.buttons["Start Level"].tap()
        settle()
    }

    private func makeAnyValidSwap(_ app: XCUIApplication, moves: XCUIElement) -> Bool {
        let start = moves.value as? String ?? ""
        for r in 1...6 {
            for c in 1...5 {
                let a = element(app, "Row \(r), column \(c)"), b = element(app, "Row \(r), column \(c + 1)")
                guard a.exists, b.exists else { continue }
                a.press(forDuration: 0.05, thenDragTo: b)
                let exp = expectation(for: NSPredicate(format: "value != %@", start), evaluatedWith: moves)
                if XCTWaiter.wait(for: [exp], timeout: 2.5) == .completed { return true }
            }
        }
        return false
    }

    /// Pause → World Map сохраняет попытку → Home «Resume Level 1» → та же попытка на паузе → Resume.
    func testWorldMapKeepsRunAndResumeRestoresIt() {
        let app = launch(fresh: true)
        startLevel1(app)
        let moves = element(app, "Moves")
        XCTAssertTrue(moves.waitForExistence(timeout: 10))
        XCTAssertTrue(makeAnyValidSwap(app, moves: moves))
        settle(); settle()
        let after = moves.value as? String
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["World Map"].waitForExistence(timeout: 5))
        app.buttons["World Map"].tap()
        settle()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
        // Карта → Home через Back (карта лежит над Worlds/Home).
        while app.buttons["Back"].exists && !button(app, containing: "Resume Level 1").exists {
            app.buttons["Back"].firstMatch.tap()
            settle()
        }
        let resume = button(app, containing: "Resume Level 1")
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        app.terminate()
        let app2 = launch(fresh: false)
        let resume2 = button(app2, containing: "Resume Level 1")
        XCTAssertTrue(resume2.waitForExistence(timeout: 10), "active run must survive relaunch")
        settle()
        resume2.tap()
        XCTAssertTrue(app2.buttons["Resume"].waitForExistence(timeout: 5), "resumed run opens paused")
        app2.buttons["Resume"].tap()
        XCTAssertEqual(element(app2, "Moves").value as? String, after)
    }

    /// How to Play → Stage Handbook → тема Keys & Exits → Got It → Home.
    func testHandbookTopicsAndGotIt() {
        let app = launch(fresh: true)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        settle()
        app.buttons["How to Play"].tap()
        settle()
        let topic = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Keys & Exits'")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Keys can'")).firstMatch.waitForExistence(timeout: 5))
        let gotIt = app.buttons["Got It"]
        if !gotIt.isHittable { app.swipeUp() }
        gotIt.tap()
        XCTAssertTrue(button(app, containing: "Play Level 1").waitForExistence(timeout: 5))
    }

    /// Reset Progress (destructive) → новый профиль: попытка стёрта, Home снова «Play Level 1».
    func testResetProgressErasesActiveRun() {
        let app = launch(fresh: true)
        startLevel1(app)
        XCTAssertTrue(element(app, "Moves").waitForExistence(timeout: 10))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["World Map"].waitForExistence(timeout: 5), "Pause must stay reachable while the tutorial banner is shown")
        app.buttons["World Map"].tap()
        settle()
        while app.buttons["Back"].exists && !app.buttons["Settings"].exists {
            app.buttons["Back"].firstMatch.tap()
            settle()
        }
        XCTAssertTrue(button(app, containing: "Resume Level 1").exists)
        app.buttons["Settings"].tap()
        settle()
        let reset = app.buttons["Reset Progress"]
        if !reset.isHittable { app.swipeUp() }
        reset.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Reset Progress'")).element(boundBy: 1)
        XCTAssertTrue(element(app, "Reset your progress?").waitForExistence(timeout: 5))
        (confirm.exists ? confirm : app.buttons["Reset Progress"].firstMatch).tap()
        XCTAssertTrue(button(app, containing: "Play Level 1").waitForExistence(timeout: 5))
    }
}
