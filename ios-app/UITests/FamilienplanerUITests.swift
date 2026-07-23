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
        "wunschliste", "gypsi", "reiniger", "elisbooks", "ebooks", "smarthome", "vertraege", "pizza",
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

    /// Deep-Link genau so auslösen, wie es Widget, Live Activity und Push tun: über das System
    /// (`familienplaner://…`). Die laufende Test-Instanz wird dadurch nach vorn geholt und bekommt
    /// den Link via `.onOpenURL` — der `-uitest`-Startzustand bleibt erhalten (kein Neustart).
    /// Gibt zurück, ob die App danach wieder im Vordergrund ist.
    @discardableResult
    private func openDeepLink(_ link: String) -> Bool {
        guard let url = URL(string: link) else {
            XCTFail("Ungültiger Deep-Link: \(link)")
            return false
        }
        XCUIDevice.shared.system.open(url)
        return waitUntil(self.app.state == .runningForeground, timeout: 15)
    }

    /// Element irgendwo im Baum über ein Identifier-Präfix suchen (Menü-Einträge sind je nach
    /// Rendering Button ODER anderer Elementtyp → `.any` statt `app.buttons`).
    private func anyElement(idPrefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", idPrefix))
            .firstMatch
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

    /// DATENGETRIEBEN (Fixture): Agenda-Zeilen mit Ort zeigen einen antippbaren „Ort"-Link (→ Google Maps).
    /// Fängt das ursprüngliche Manko (Termine ohne Uhrzeit/Ort) — der Fixture-Termin hat beides.
    func testHomeAgendaShowsTappableLocation() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        // Der Ort ist ein eigener antippbarer Link (mind. einmal: „Als Nächstes"-Karte + Agenda-Zeile).
        let loc = app.buttons["agenda-location"].firstMatch
        XCTAssertTrue(loc.waitForExistence(timeout: 10), "Ort-Link in der Agenda fehlt")
        XCTAssertTrue(loc.label.contains("Dr. Test"), "Ort-Link zeigt den Ortsnamen nicht (label=\(loc.label))")
        // Die Uhrzeit des Fixture-Termins muss in der Agenda stehen (Untertitel „… · 10:00 · …").
        // .matching filtert nach dem EIGENEN Label jedes staticText (nicht nach Nachfahren wie .containing).
        let withTime = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "10:00")).firstMatch
        XCTAssertTrue(withTime.waitForExistence(timeout: 6), "Uhrzeit fehlt in der Agenda-Zeile")
    }

    /// DATENGETRIEBEN (Fixture): Home zeigt die neue „Aufgaben"-Section mit Aufgaben (Familie + Garten),
    /// dem Hinzufügen-Button (öffnet das Anlege-Sheet) und den Abhaken-Kreisen.
    func testHomeShowsAufgabenSection() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        XCTAssertTrue(app.staticTexts["Aufgaben"].waitForExistence(timeout: 12), "Aufgaben-Section fehlt")
        XCTAssertTrue(app.staticTexts["UITEST Steuer"].waitForExistence(timeout: 8), "Fixture-Aufgabe fehlt")
        XCTAssertTrue(app.buttons["aufgabe-complete-aufgabe-1"].waitForExistence(timeout: 6), "Abhaken-Kreis fehlt")
        // Hinzufügen-Button in Sicht scrollen und Anlege-Sheet öffnen.
        let addBtn = app.buttons["aufgabe-add"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 6), "Hinzufügen-Button fehlt")
        var tries = 0
        while !addBtn.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        addBtn.tap()
        XCTAssertTrue(app.textFields["Was ist zu tun? *"].waitForExistence(timeout: 8), "Aufgabe-Anlegen-Sheet öffnet nicht")
    }

    /// DATENGETRIEBEN (Fixture): Home zeigt die „Bald ablaufend"-Section mit ablaufenden Lebensmitteln.
    func testHomeShowsVorratAblaufend() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        // Eindeutig die Section (nicht die gleichnamige KPI-Kachel): Zeilen-Button + Produktname aus der Fixture.
        XCTAssertTrue(app.buttons["vorrat-ablaufend-1"].waitForExistence(timeout: 12), "Bald-ablaufend-Zeile fehlt")
        XCTAssertTrue(app.staticTexts["UITEST Joghurt"].waitForExistence(timeout: 6), "Ablaufendes Lebensmittel fehlt")
    }

    /// DATENGETRIEBEN (Fixture): der KI-Rezept-Button in „Bald ablaufend" öffnet ein Sheet mit Rezept.
    func testHomeRezeptVorschlag() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        let btn = app.buttons["vorrat-rezept-ki"]
        XCTAssertTrue(btn.waitForExistence(timeout: 12), "KI-Rezept-Button fehlt")
        var tries = 0
        while !btn.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        btn.tap()
        // Titel trägt die accessibilityIdentifier "rezept-titel" → per ID suchen (Label-Subscript würde
        // wegen der gesetzten ID nicht auflösen), dann den echten Titel-Text prüfen.
        let titel = app.staticTexts["rezept-titel"]
        XCTAssertTrue(titel.waitForExistence(timeout: 8), "KI-Rezept-Sheet zeigt kein Rezept (Fixture nicht geladen?)")
        XCTAssertTrue(titel.label.contains("Joghurt-Pfanne"), "Rezept-Titel falsch (label=\(titel.label))")
    }

    /// DATENGETRIEBEN (Fixture): der „Erledigt"-Umschalter zeigt kürzlich abgehakte Aufgaben mit
    /// Wieder-Öffnen-Kreis (Undo bei versehentlichem Abhaken).
    func testHomeAufgabenErledigtFilter() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        XCTAssertTrue(app.staticTexts["Aufgaben"].waitForExistence(timeout: 12), "Aufgaben-Section fehlt")
        // Segment „Erledigt" wählen — robust: erst innerhalb des SegmentedControls, sonst app-weit als Button.
        let scoped = app.segmentedControls.buttons["Erledigt"]
        let erledigt = scoped.waitForExistence(timeout: 4) ? scoped : app.buttons["Erledigt"]
        var tries = 0
        while !erledigt.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(erledigt.waitForExistence(timeout: 6), "Erledigt-Segment fehlt")
        erledigt.tap()
        XCTAssertTrue(app.staticTexts["UITEST Erledigt Paket"].waitForExistence(timeout: 6), "Erledigte Aufgabe fehlt")
        XCTAssertTrue(app.buttons["aufgabe-complete-aufgabe-9"].waitForExistence(timeout: 4), "Wieder-Öffnen-Kreis fehlt")
    }

    /// DATENGETRIEBEN (Fixture): Home zeigt die Alarmanlage-Kachel (Alarmo, unscharf) mit „Aktivieren"-Menü.
    func testHomeShowsAlarmoTile() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Heute-Tab fehlt")
        tabButton("Heute").tap()
        XCTAssertTrue(app.staticTexts["Alarmanlage"].waitForExistence(timeout: 10), "Alarmanlage-Kachel fehlt")
        XCTAssertTrue(app.buttons["alarmo-arm"].waitForExistence(timeout: 6), "Aktivieren-Steuerung fehlt (Zustand disarmed)")
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
        // Kameras zuerst prüfen, SOLANGE oben (die Kamera-LazyVGrid recycelt ihre Zellen aus dem
        // Baum, sobald man nach unten zu den Szenen scrollt) — Snapshot trifft im Test kein Backend.
        XCTAssertTrue(app.staticTexts["Kameras"].waitForExistence(timeout: 8), "Kamera-Sektion fehlt")
        XCTAssertTrue(app.buttons["camera-camera.einfahrt_high"].waitForExistence(timeout: 8), "Kamera-Kachel 'Einfahrt' fehlt")
        // Szenen liegen unten im ScrollView in einer LazyVGrid → erst einscrollen, damit die Zellen
        // instanziiert werden (off-screen existieren sie nicht im Accessibility-Baum).
        let putzen = app.buttons["script-script.raffstore_putzen"]
        var tries = 0
        while !putzen.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(putzen.waitForExistence(timeout: 8), "Szenen-Button 'Putzen' fehlt")
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
        XCTAssertTrue(app.buttons["calibre-download-epub"].waitForExistence(timeout: 6), "EPUB-Download-Button fehlt")
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

    /// DATENGETRIEBEN (lokal gerechnet): der Pizza-Planer rechnet auf dem Gerät, nicht im Backend —
    /// im -uitest-Lauf (ohne Backend) MUSS deshalb trotzdem eine Startzeit + ein Zeitplan dastehen.
    /// Die Rezeptur-Liste hängt dagegen am Backend und darf leer bleiben; geprüft wird dort nur,
    /// dass der Segment-Wechsel den Planer-Inhalt austauscht und zurück wieder herstellt.
    func testPizzaPlaner() {
        openBereiche()
        let tileEl = tile("pizza")
        XCTAssertTrue(tileEl.waitForExistence(timeout: 8), "Pizza-Kachel fehlt")
        tileEl.tap()

        // Startzeit = die Antwort des Planers (Standard-Essenszeit hat immer genug Vorlauf → kein Problem-Zustand).
        // Zeitplan-Karte ist ein Accessibility-Container (children: .contain) → über .any suchen, nicht über staticTexts.
        let startzeit = app.descendants(matching: .any)["pizza-startzeit"]
        XCTAssertTrue(startzeit.waitForExistence(timeout: 12),
                      "Startzeit-Anzeige fehlt — der Planer hat ohne Backend nicht gerechnet")
        let zeitplan = app.descendants(matching: .any)["pizza-zeitplan"]
        XCTAssertTrue(zeitplan.waitForExistence(timeout: 8), "Zeitplan-Karte fehlt")

        // Segment 'Rezepturen': Planer-Inhalt muss verschwinden (Liste selbst darf leer/ladend sein).
        let rezepturen = app.buttons["segment-Rezepturen"]
        XCTAssertTrue(rezepturen.waitForExistence(timeout: 8), "Segment 'Rezepturen' fehlt")
        rezepturen.tap()
        XCTAssertTrue(waitUntil(!startzeit.exists), "Segment 'Rezepturen' hat nicht umgeschaltet")

        // Zurück auf 'Planer': der Plan ist wieder da.
        let planer = app.buttons["segment-Planer"]
        XCTAssertTrue(planer.waitForExistence(timeout: 8), "Segment 'Planer' fehlt")
        planer.tap()
        XCTAssertTrue(waitUntil(startzeit.exists), "Segment 'Planer' hat nicht zurückgeschaltet")

        goBack()
        XCTAssertTrue(waitUntil(tileEl.isHittable), "Zurück aus dem Pizza-Bereich fehlgeschlagen")
    }

    // MARK: - Termin-Widgets / Push-Quittierung (das in XCUITest Testbare)
    //
    // Widgets, Live Activities und die Sperrbildschirm-Aktionen selbst laufen in eigenen Prozessen
    // (WidgetKit-Extension bzw. SpringBoard) und sind mit XCUITest NICHT ansteuerbar. Testbar ist
    // die App-Seite dieser Features: das Deep-Link-Routing (Widget-/Push-Tap) und die neue
    // Stumm-Aktion in der Termin-Karte.

    /// Deep-Link `familienplaner://termine` (Widget-Tap / Push-Tap) öffnet den Termine-Bereich.
    /// Vorher wird bewusst auf einen anderen Tab gewechselt, damit der Test nicht nur den
    /// Startzustand misst, sondern die tatsächliche Navigation.
    func testDeepLinkOpensTermineBereich() {
        XCTAssertTrue(tabButton("Inbox").waitForExistence(timeout: 15), "Tab-Bar fehlt")
        tabButton("Inbox").tap()
        XCTAssertTrue(waitUntil(!self.app.staticTexts["Familie Paetzold-Stilke"].exists),
                      "Termine-Bereich war schon vor dem Deep-Link offen")

        XCTAssertTrue(openDeepLink("familienplaner://termine"),
                      "App ist nach dem Deep-Link nicht in den Vordergrund gekommen")
        XCTAssertTrue(app.staticTexts["Familie Paetzold-Stilke"].waitForExistence(timeout: 15),
                      "Deep-Link 'termine' hat nicht in den Termine-Bereich navigiert")
    }

    /// Deep-Link `familienplaner://termin-neu` (Quick-Actions-Widget) öffnet den Termine-Bereich
    /// UND direkt das Anlege-Formular. Deckt die Kette AppState.handleDeepLink →
    /// pendingTerminNew → TermineListView.consumeDeepLink → Sheet ab (läuft ohne Backend).
    func testDeepLinkTerminNeuOpensFormular() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Tab-Bar fehlt")

        XCTAssertTrue(openDeepLink("familienplaner://termin-neu"),
                      "App ist nach dem Deep-Link nicht in den Vordergrund gekommen")
        XCTAssertTrue(app.textFields["Was steht an? *"].waitForExistence(timeout: 20),
                      "Deep-Link 'termin-neu' hat das Anlege-Formular nicht geöffnet")
    }

    /// Deep-Link `familienplaner://inbox` (Foto-Push) schaltet auf den Inbox-Tab.
    func testDeepLinkOpensInbox() {
        XCTAssertTrue(tabButton("Heute").waitForExistence(timeout: 15), "Tab-Bar fehlt")
        tabButton("Heute").tap()

        XCTAssertTrue(openDeepLink("familienplaner://inbox"),
                      "App ist nach dem Deep-Link nicht in den Vordergrund gekommen")
        let inbox = tabButton("Inbox")
        XCTAssertTrue(inbox.waitForExistence(timeout: 10), "Inbox-Tab fehlt")
        // Doppelt abgesichert: ausgewählter Tab ODER die Inbox-Navigationsleiste ist da
        // (die Auswahl-Markierung der Liquid-Glass-Tab-Bar ist je nach Layout nicht gesetzt).
        XCTAssertTrue(waitUntil(inbox.isSelected || self.app.navigationBars["Inbox"].exists, timeout: 10),
                      "Deep-Link 'inbox' hat nicht auf den Inbox-Tab geschaltet")
    }

    /// Die neue Stumm-Aktion im Benachrichtigungs-Menü der Termin-Karte (gleiche Route wie die
    /// Push-Aktion „Nicht mehr erinnern" am Sperrbildschirm).
    ///
    /// EHRLICHER HINWEIS: der `-uitest`-Lauf hat kein Backend, und für `/termine` gibt es (Stand
    /// jetzt) KEINE Fixture in `UITestFixtures` → es existiert keine Termin-Karte, an der das Menü
    /// hängen könnte. Statt einen Scheintest grün zu melden, wird der Test dann sauber
    /// ÜBERSPRUNGEN. Sobald eine `/termine`-Fixture ergänzt ist (`UITestFixtures.array` →
    /// `case "/termine"`), greift er automatisch und prüft das Menü echt.
    func testTerminCardNotifyMenuHasMuteAction() throws {
        openBereiche()
        let t = tile("termine")
        XCTAssertTrue(t.waitForExistence(timeout: 10), "Termine-Kachel fehlt")
        t.tap()
        XCTAssertTrue(app.staticTexts["Familie Paetzold-Stilke"].waitForExistence(timeout: 15),
                      "Termine-Bereich öffnet nicht")

        // Menü-Anker der Karte: Glocke mit Identifier "termin-notify-<id>".
        let notify = anyElement(idPrefix: "termin-notify-")
        try XCTSkipUnless(
            notify.waitForExistence(timeout: 8),
            "Keine Termin-Karte im -uitest-Lauf (kein Backend, keine /termine-Fixture) — Stumm-Menü nicht prüfbar")
        notify.tap()

        // Menü-Einträge über den Identifier suchen (Label-Subscript matcht bei gesetzter ID nicht).
        // Fallback über das Label nur, falls SwiftUI die ID nicht ins UIMenu durchreicht.
        let byId = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'termin-mute-' OR identifier BEGINSWITH 'termin-unmute-'")
        ).firstMatch
        let byLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "erinnern")
        ).firstMatch
        XCTAssertTrue(waitUntil(byId.exists || byLabel.exists, timeout: 8),
                      "Benachrichtigungs-Menü der Termin-Karte enthält keinen Stumm-Eintrag")
    }
}
