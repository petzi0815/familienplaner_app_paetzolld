import XCTest

/// GUI-Navigations-Smoke: startet die App im UI-Test-Modus (Login übersprungen, Bereiche statisch),
/// prüft dass alle Tabs erreichbar sind, jede Bereichs-Kachel navigiert + Zurück funktioniert,
/// und die Segment-Tabs der nativen Bereiche schalten. Läuft OHNE Backend (deterministisch).
final class FamilienplanerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Sicherheitsnetz: unerwartete System-Dialoge (Berechtigungen) wegtippen.
        addUIInterruptionMonitor(withDescription: "System-Dialog") { alert in
            for label in ["Erlauben", "Allow", "OK", "Fertig", "Schließen", "Zulassen"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
    }

    // Alle Domain-Keys (Reihenfolge = DomainCatalog.order).
    private let domainKeys = [
        "termine", "abfuhrkalender", "reisen", "samu", "geschenkplaner", "garten", "vorratskammer",
        "wunschliste", "gypsi", "reiniger", "elisbooks", "ebooks", "smarthome", "vertraege",
    ]

    // MARK: - Helfer

    private func waitUntil(_ cond: @autoclosure () -> Bool, timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return cond()
    }

    private func tabButton(_ label: String) -> XCUIElement { app.tabBars.buttons[label] }

    private func openBereiche() {
        let btn = tabButton("Bereiche")
        XCTAssertTrue(btn.waitForExistence(timeout: 10), "Tab 'Bereiche' fehlt")
        btn.tap()
    }

    /// Kachel in Sicht scrollen und zurückgeben.
    private func tile(_ key: String) -> XCUIElement {
        let el = app.buttons["bereich-tile-\(key)"]
        var tries = 0
        while !el.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        return el
    }

    private func goBack() {
        // Zurück-Chevron ist das erste Navigations-Bar-Element der gepushten Ansicht.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    // MARK: - Tests

    /// App startet in die Tab-Bar (nicht in den Login).
    func testLaunchesToMainTabView() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "App landet nicht in der Tab-Bar (Login nicht übersprungen?)")
        XCTAssertTrue(tabButton("Bereiche").exists)
        // Login-Screen darf NICHT sichtbar sein.
        XCTAssertFalse(app.secureTextFields["API-Key"].exists, "Login-Screen sichtbar — Bypass hat nicht gegriffen")
    }

    /// Jeder Tab ist antippbar und die App bleibt am Leben.
    func testTabBarNavigation() {
        for label in ["Heute", "Bereiche", "Erfassen", "Inbox", "Suchen"] {
            let b = tabButton(label)
            XCTAssertTrue(b.waitForExistence(timeout: 8), "Tab '\(label)' fehlt")
            b.tap()
            XCTAssertTrue(waitUntil(self.app.state == .runningForeground), "App nach Tab '\(label)' nicht mehr aktiv")
        }
    }

    /// Jede Bereichs-Kachel navigiert in ihre Ansicht und Zurück kehrt zurück.
    func testAllBereicheTilesNavigateAndBack() {
        openBereiche()
        // Grid da?
        XCTAssertTrue(app.buttons["bereich-tile-termine"].waitForExistence(timeout: 12), "Bereiche-Grid leer")

        for key in domainKeys {
            let t = tile(key)
            guard t.waitForExistence(timeout: 6) else { XCTFail("Kachel fehlt: \(key)"); continue }
            XCTAssertTrue(t.isHittable, "Kachel nicht antippbar: \(key)")
            t.tap()
            // Navigation erfolgt → Zurück-Button erscheint, Kachel nicht mehr sichtbar.
            XCTAssertTrue(waitUntil(self.app.navigationBars.buttons.element(boundBy: 0).exists && !t.isHittable),
                          "Kachel '\(key)' hat nicht navigiert")
            goBack()
            XCTAssertTrue(waitUntil(t.isHittable), "Zurück aus '\(key)' fehlgeschlagen")
        }
    }

    /// Native Bereiche mit Segment-Navigation: sichtbare Segmente lassen sich antippen.
    /// (Segmente in der horizontalen Scroll-Leiste, die aus dem Bild laufen, werden übersprungen —
    /// Hittability off-screen zu prüfen wirft in XCUITest.)
    func testNativeAreaSegmentsSwitch() {
        openBereiche()
        let screen = app.windows.firstMatch.frame
        for key in ["samu", "garten", "geschenkplaner", "vorratskammer", "wunschliste", "termine", "reiniger", "gypsi", "smarthome", "vertraege", "ebooks"] {
            let t = tile(key)
            guard t.waitForExistence(timeout: 5), t.isHittable else { continue }
            t.tap()
            _ = waitUntil(self.app.navigationBars.buttons.element(boundBy: 0).exists)
            // Nur vollständig sichtbare Segment-Buttons antippen (Frame innerhalb des Bildschirms).
            let segments = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'segment-'"))
            let count = min(segments.count, 8)
            for i in 0..<count {
                let seg = segments.element(boundBy: i)
                guard seg.exists else { continue }
                let f = seg.frame
                guard f.width > 1, f.minX >= screen.minX, f.maxX <= screen.maxX else { continue }
                seg.tap()
                XCTAssertTrue(waitUntil(self.app.state == .runningForeground), "App tot nach Segment in '\(key)'")
            }
            goBack()
            _ = waitUntil(t.isHittable)
        }
    }
}
