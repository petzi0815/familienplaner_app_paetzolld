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
        for label in ["Heute", "Bereiche", "Erfassen", "Inbox", "Smarthome"] {
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

    /// DATENGETRIEBEN (Fixture): Home zeigt die 6 KPI-Kacheln, die Agenda, den Abonnieren-Button
    /// und (Fixture-Build 999 > installiert) das Update-Banner.
    func testHomeShowsKpisAgendaAndUpdateBanner() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        for key in ["foto", "termine", "reminders", "vorrat", "nachkaufen", "geschenke"] {
            XCTAssertTrue(app.buttons["kpi-\(key)"].waitForExistence(timeout: 10), "KPI-Kachel fehlt: \(key)")
        }
        XCTAssertTrue(app.buttons["calendar-subscribe"].waitForExistence(timeout: 8), "Abonnieren-Button fehlt")
        XCTAssertTrue(app.staticTexts["UITEST Zahnarzt"].waitForExistence(timeout: 8), "Agenda-Eintrag fehlt")
        XCTAssertTrue(app.buttons["update-banner"].waitForExistence(timeout: 10), "Update-Banner fehlt")
    }

    /// DATENGETRIEBEN (Fixture): Home zeigt die Alarmanlage-Kachel (Alarmo, unscharf) mit „Aktivieren"-Menü.
    func testHomeShowsAlarmoTile() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        XCTAssertTrue(app.staticTexts["Alarmanlage"].waitForExistence(timeout: 10), "Alarmanlage-Kachel fehlt")
        XCTAssertTrue(app.buttons["alarmo-arm"].waitForExistence(timeout: 6), "„Aktivieren"-Steuerung fehlt (Zustand disarmed)")
    }

    /// Suche ist oben rechts auf „Heute" erreichbar (Toolbar-Button öffnet die Such-Ansicht als Sheet).
    func testHomeSearchButtonOpensSearch() {
        tabButton("Heute").tap()
        let search = app.buttons["home-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Such-Button oben rechts fehlt")
        search.tap()
        XCTAssertTrue(app.navigationBars["Suchen"].waitForExistence(timeout: 8), "Such-Ansicht öffnet nicht")
    }

    /// DATENGETRIEBEN (Fixture): der Smart-Home-Tab zeigt Alarmanlage, Raffstores und Szenen-Buttons.
    func testSmarthomeTabShowsControls() {
        let tab = tabButton("Smarthome")
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "Smarthome-Tab fehlt")
        tab.tap()
        XCTAssertTrue(app.staticTexts["Alarmanlage"].waitForExistence(timeout: 10), "Alarmanlage-Kachel fehlt im Smarthome-Tab")
        XCTAssertTrue(app.staticTexts["Raffstores"].waitForExistence(timeout: 8), "Raffstore-Sektion fehlt")
        XCTAssertTrue(app.staticTexts["Küche"].waitForExistence(timeout: 8), "Raffstore 'Küche' fehlt")
        XCTAssertTrue(app.buttons["script-script.raffstore_putzen"].waitForExistence(timeout: 8), "Szenen-Button 'Putzen' fehlt")
        // Kameras: Sektion + eine Kamera-Kachel (Snapshot trifft im Test kein Backend, Kachel existiert trotzdem).
        XCTAssertTrue(app.staticTexts["Kameras"].waitForExistence(timeout: 8), "Kamera-Sektion fehlt")
        XCTAssertTrue(app.buttons["camera-camera.einfahrt_high"].waitForExistence(timeout: 8), "Kamera-Kachel 'Einfahrt' fehlt")
    }

    /// KPI-Kachel „Anstehende Termine" tippen → springt in den Termine-Bereich.
    func testHomeKpiNavigatesToBereich() {
        tabButton("Heute").tap()
        let kpi = app.buttons["kpi-termine"]
        XCTAssertTrue(kpi.waitForExistence(timeout: 12), "KPI-Kachel 'termine' fehlt")
        kpi.tap()
        XCTAssertTrue(app.staticTexts["Familie Paetzold-Stilke"].waitForExistence(timeout: 12),
                      "KPI-Tap hat nicht in den Termine-Bereich navigiert")
    }

    /// DATENGETRIEBEN (Fixture): externe E-Book-Suche liefert einen Treffer.
    func testEbookExternalSearchReturnsResults() {
        openBereiche()
        let tileEl = tile("ebooks")
        guard tileEl.waitForExistence(timeout: 8) else { XCTFail("E-Books-Kachel fehlt"); return }
        tileEl.tap()
        let seg = app.buttons["segment-Buch suchen"]
        XCTAssertTrue(seg.waitForExistence(timeout: 8), "Segment 'Buch suchen' fehlt")
        seg.tap()
        let field = app.textFields["ebook-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Suchfeld fehlt")
        field.tap()
        field.typeText("test")
        app.buttons["ebook-search-button"].tap()
        XCTAssertTrue(app.staticTexts["UITEST Testbuch"].waitForExistence(timeout: 8),
                      "Externe Suche liefert kein Ergebnis (Fixture nicht geladen?)")
    }

    /// DATENGETRIEBEN (Fixture): E-Books „Bibliothek"-Tab (Calibre) zeigt Regale + Bücher.
    func testCalibreLibraryTab() {
        openBereiche()
        let tileEl = tile("ebooks")
        guard tileEl.waitForExistence(timeout: 8) else { XCTFail("E-Books-Kachel fehlt"); return }
        tileEl.tap()
        let seg = app.buttons["segment-Bibliothek"]
        XCTAssertTrue(seg.waitForExistence(timeout: 8), "Segment 'Bibliothek' fehlt")
        seg.tap()
        XCTAssertTrue(app.staticTexts["UITEST Bibliotheksbuch"].waitForExistence(timeout: 8),
                      "Calibre-Bibliothek zeigt kein Buch (Fixture nicht geladen?)")
        XCTAssertTrue(app.buttons["calibre-shelf-2"].waitForExistence(timeout: 4), "Regal-Filter fehlt")
        XCTAssertTrue(app.buttons["calibre-sort"].exists, "Sortier-Menü fehlt")

        // Buch antippen → Detailseite mit Metadaten + Regal-Zuordnung.
        app.buttons["calibre-book-5356"].tap()
        XCTAssertTrue(app.staticTexts["Test Verlag"].waitForExistence(timeout: 8), "Buch-Detail zeigt keine Metadaten")
        XCTAssertTrue(app.buttons["calibre-detail-shelf-2"].waitForExistence(timeout: 6), "Regal-Zuordnung im Detail fehlt")
    }

    /// DATENGETRIEBEN (Fixture): Geschenkplaner-Event antippen → Detail öffnet sich → Zurück.
    /// Fängt den Navigations-Bug (Tap „verschluckt") UND die Jahres-Formatierung (2.026 statt 2026).
    func testGeschenkplanerEventNavigation() {
        openBereiche()
        let tileEl = tile("geschenkplaner")
        XCTAssertTrue(tileEl.waitForExistence(timeout: 8), "Geschenkplaner-Kachel fehlt")
        tileEl.tap()

        // Dashboard-Event aus der Fixture muss erscheinen.
        let event = app.buttons["gp-event-1"]
        XCTAssertTrue(event.waitForExistence(timeout: 12), "Geschenkplaner-Dashboard zeigt kein Event (Fixture nicht geladen?)")

        // Jahr korrekt gerendert — NICHT mit Tausendertrennung „2.026".
        let grouped = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2.026")).firstMatch
        XCTAssertFalse(grouped.exists, "Jahr mit Tausendertrennung gerendert (2.026 statt 2026)")

        // Event antippen → Ereignis-Detail muss sich öffnen (fixt den Navigations-Bug).
        event.tap()
        XCTAssertTrue(app.staticTexts["Test-Geschenk A"].waitForExistence(timeout: 8),
                      "Event-Tap hat nicht ins Detail navigiert (Navigations-Bug)")

        // Zurück muss auf das Dashboard führen (nicht erst das Detail zeigen).
        goBack()
        XCTAssertTrue(waitUntil(event.isHittable), "Zurück aus dem Ereignis-Detail fehlgeschlagen")
    }
}
