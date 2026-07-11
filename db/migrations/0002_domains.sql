-- 0002_domains — Domänen-Tabellen (aus Legacy-SQLite konsolidiert, präfixiert, FK umgeschrieben).
-- GENERIERT von scripts/gen-domain-migration.mjs — nicht von Hand editieren.

-- ── termine.db ──
CREATE TABLE IF NOT EXISTS "termine" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL DEFAULT 'allgemein',
    date TEXT NOT NULL,
    time TEXT,
    end_date TEXT,
    end_time TEXT,
    location TEXT,
    person TEXT,
    recurring TEXT,
    recurring_interval TEXT,
    reminder_days INTEGER DEFAULT 2,
    reminder_sent INTEGER DEFAULT 0,
    cron_job_id TEXT,
    status TEXT DEFAULT 'offen',
    notes TEXT,
    source TEXT DEFAULT 'manuell',
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

-- ── reisen.db ──
CREATE TABLE IF NOT EXISTS "reisen_trips" (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, type TEXT DEFAULT "urlaub", status TEXT DEFAULT "geplant", start_date TEXT, end_date TEXT, destination TEXT, country TEXT, region TEXT, lat REAL, lng REAL, hotel TEXT, hotel_url TEXT, booking_ref TEXT, booking_platform TEXT, flight TEXT, flight_ref TEXT, transport TEXT, budget TEXT, cost_total TEXT, currency TEXT DEFAULT "EUR", participants TEXT DEFAULT "Familie", activities TEXT, highlights TEXT, rating INTEGER, cover_image TEXT, notes TEXT, source TEXT DEFAULT "manuell", tags TEXT, created_at TEXT, updated_at TEXT, destination_info TEXT, timezone_offset INTEGER DEFAULT 0, timezone_name TEXT);

CREATE TABLE IF NOT EXISTS "reisen_trip_activities" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    category TEXT DEFAULT 'sehenswuerdigkeit',
    description TEXT,
    details TEXT,
    location TEXT,
    lat REAL,
    lng REAL,
    google_maps_url TEXT,
    tripadvisor_url TEXT,
    website_url TEXT,
    image_url TEXT,
    duration TEXT,
    price TEXT,
    kid_friendly INTEGER DEFAULT 1,
    kid_notes TEXT,
    best_time TEXT,
    tips TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TEXT,
    FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
  );

CREATE TABLE IF NOT EXISTS "reisen_trip_day_plans" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  day_number INTEGER NOT NULL,
  day_date TEXT,
  title TEXT,
  time_slot TEXT,
  activity TEXT NOT NULL,
  activity_id INTEGER,
  location TEXT,
  emoji TEXT DEFAULT '📍',
  notes TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_diving" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id INTEGER NOT NULL,
    dive_center_name TEXT,
    description TEXT,
    location TEXT,
    lat REAL,
    lng REAL,
    google_maps_url TEXT,
    tripadvisor_url TEXT,
    website_url TEXT,
    certifications TEXT,
    highlights TEXT,
    conditions TEXT,
    price_range TEXT,
    kid_notes TEXT,
    tips TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TEXT,
    FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
  );

CREATE TABLE IF NOT EXISTS "reisen_trip_docs" (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER NOT NULL, name TEXT NOT NULL, doc_type TEXT DEFAULT "sonstig", mime_type TEXT, file_data BLOB, file_size INTEGER, text_content TEXT, url TEXT, notes TEXT, created_at TEXT, FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE);

CREATE TABLE IF NOT EXISTS "reisen_trip_emails" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id INTEGER NOT NULL,
    email_subject TEXT,
    email_from TEXT,
    email_date TEXT,
    email_snippet TEXT,
    email_db_id INTEGER,
    category TEXT DEFAULT 'allgemein',
    created_at TEXT,
    FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
  );

CREATE TABLE IF NOT EXISTS "reisen_trip_emergency" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  url TEXT,
  lat REAL,
  lng REAL,
  notes TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_flights" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  direction TEXT NOT NULL DEFAULT "outbound",  -- outbound / return
  airline TEXT,
  airline_code TEXT,
  flight_number TEXT,
  departure_airport TEXT,
  departure_code TEXT,
  departure_time TEXT,
  arrival_airport TEXT,
  arrival_code TEXT,
  arrival_time TEXT,
  duration TEXT,
  aircraft_type TEXT,
  booking_ref TEXT,
  seat_info TEXT,
  gate TEXT,
  terminal TEXT,
  status TEXT DEFAULT "scheduled",  -- scheduled / boarding / departed / arrived / delayed / cancelled
  delay_minutes INTEGER,
  baggage_belt TEXT,
  checkin_url TEXT,
  notes TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_hotel" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL UNIQUE,
  name TEXT,
  category TEXT,
  room_type TEXT,
  board_type TEXT,
  check_in TEXT,
  check_out TEXT,
  amenities TEXT,
  pools TEXT,
  spa TEXT,
  kids_club TEXT,
  restaurants_info TEXT,
  wifi TEXT,
  parking TEXT,
  beach TEXT,
  website_url TEXT,
  booking_url TEXT,
  tripadvisor_url TEXT,
  holidaycheck_url TEXT,
  description TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_links" (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, link_type TEXT DEFAULT "info", description TEXT, image_url TEXT, created_at TEXT, FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE);

CREATE TABLE IF NOT EXISTS "reisen_trip_packing" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  item TEXT NOT NULL,
  quantity INTEGER DEFAULT 1,
  packed INTEGER DEFAULT 0,
  notes TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_phrases" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  local_text TEXT NOT NULL,
  pronunciation TEXT,
  german TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_restaurants" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    cuisine TEXT,
    description TEXT,
    specialties TEXT,
    location TEXT,
    lat REAL,
    lng REAL,
    google_maps_url TEXT,
    tripadvisor_url TEXT,
    website_url TEXT,
    menu_url TEXT,
    image_url TEXT,
    price_range TEXT,
    kid_friendly INTEGER DEFAULT 1,
    kid_notes TEXT,
    reservation_needed INTEGER DEFAULT 0,
    reservation_url TEXT,
    opening_hours TEXT,
    tips TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TEXT, vegetarian_options TEXT,
    FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
  );

CREATE TABLE IF NOT EXISTS "reisen_trip_samu_activities" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  details TEXT,
  emoji TEXT DEFAULT '👶',
  category TEXT DEFAULT 'hotel',
  location TEXT,
  age_range TEXT,
  equipment_needed TEXT,
  safety_notes TEXT,
  tips TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "reisen_trip_weather" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id INTEGER NOT NULL,
    type TEXT DEFAULT 'historical',
    date TEXT,
    temp_min REAL,
    temp_max REAL,
    temp_water REAL,
    rain_mm REAL,
    rain_days INTEGER,
    sun_hours REAL,
    humidity REAL,
    wind_kmh REAL,
    description TEXT,
    source TEXT,
    updated_at TEXT,
    FOREIGN KEY (trip_id) REFERENCES "reisen_trips"(id) ON DELETE CASCADE
  );

CREATE TABLE IF NOT EXISTS "reisen_weekend_tips" (id INTEGER PRIMARY KEY AUTOINCREMENT, calendar_week INTEGER NOT NULL, year INTEGER NOT NULL, title TEXT NOT NULL, description TEXT, location TEXT, lat REAL, lng REAL, url TEXT, image_url TEXT, category TEXT, date_info TEXT, price TEXT, kid_friendly INTEGER DEFAULT 1, created_at TEXT, details TEXT, google_maps_url TEXT, tripadvisor_url TEXT, website_url TEXT, tips TEXT, kid_notes TEXT, address TEXT, opening_hours TEXT, distance_from_home TEXT, weather_dependent INTEGER DEFAULT 1, indoor_alternative TEXT, is_event INTEGER DEFAULT 0, priority INTEGER DEFAULT 0, UNIQUE(year, calendar_week, title));

-- ── samu-inventar.db ──
CREATE TABLE IF NOT EXISTS "samu_items" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    -- Basis-Infos
    typ TEXT NOT NULL CHECK(typ IN ('kleidung', 'spielzeug')),
    kategorie TEXT NOT NULL,
    unterkategorie TEXT,
    name TEXT,
    marke TEXT,
    beschreibung TEXT,
    
    -- Größe/Alter
    groesse TEXT,                    -- Kleidergröße (56-116) oder Schuhgröße
    altersgruppe TEXT,               -- 0-6M, 6-12M, 1-2J, 2-3J, 3+J
    passt_ab_groesse TEXT,           -- Für eingelagerte Items
    passt_ab_alter TEXT,             -- Für eingelagerte Items
    
    -- Zustand & Wert
    zustand TEXT CHECK(zustand IN ('neu', 'sehr_gut', 'gut', 'gebraucht')),
    verkaufswert REAL,               -- Geschätzter Preis in Euro
    
    -- Optik
    farbe TEXT,
    saison TEXT CHECK(saison IN ('sommer', 'winter', 'ganzjaehrig')),
    material TEXT,
    
    -- Status
    status TEXT DEFAULT 'aktiv' CHECK(status IN ('aktiv', 'eingelagert', 'aussortiert', 'verkauft', 'verschenkt')),
    verkaufskanal TEXT,              -- vinted, kleinanzeigen, etc.
    
    -- Bilder (mehrere möglich, kommasepariert oder in separater Tabelle)
    bild_pfade TEXT,                 -- Pfade zu Originalbildern (JSON Array)
    bild_telegram_ids TEXT,          -- Telegram file_ids (JSON Array)
    
    -- Timestamps
    erfasst_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aktualisiert_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aussortiert_am DATETIME,
    
    -- Notizen
    notizen TEXT
);

CREATE TABLE IF NOT EXISTS "samu_marken" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  groessen_info TEXT,
  herkunft TEXT,
  material_fokus TEXT,
  website TEXT,
  preis_segment TEXT,
  notizen TEXT,
  angereichert_am TEXT,
  erstellt_am TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS "samu_bedarfsliste" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      beschreibung TEXT NOT NULL,
      kategorie TEXT,
      groesse TEXT,
      prioritaet TEXT DEFAULT 'normal',
      notizen TEXT,
      erledigt INTEGER DEFAULT 0,
      erledigt_am TEXT,
      erstellt_am TEXT DEFAULT (datetime('now')),
      aktualisiert_am TEXT DEFAULT (datetime('now'))
    );

-- ── wunschliste.db ──
CREATE TABLE IF NOT EXISTS "wunschliste_events" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    emoji TEXT DEFAULT '🎁',
    date TEXT,
    type TEXT DEFAULT 'einmalig',
    recurring_month INTEGER,
    recurring_day INTEGER,
    notes TEXT,
    archived INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  , erinnerungen_aktiv INTEGER DEFAULT 1);

CREATE TABLE IF NOT EXISTS "wunschliste_items" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    price TEXT,
    url TEXT,
    image_url TEXT,
    category TEXT,
    priority INTEGER DEFAULT 0,
    status TEXT DEFAULT 'offen',
    purchased_by TEXT,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')), ean TEXT, price_comparison TEXT,
    FOREIGN KEY (event_id) REFERENCES "wunschliste_events"(id) ON DELETE CASCADE
  );

-- ── geschenkplaner.db ──
CREATE TABLE IF NOT EXISTS "geschenk_kinder" (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          geburtsdatum TEXT,
          profil TEXT,
          negativliste TEXT,
          profil_bestaetigt_am TEXT,
          erstellt_am TEXT DEFAULT (datetime('now')),
          aktualisiert_am TEXT DEFAULT (datetime('now'))
        );

CREATE TABLE IF NOT EXISTS "geschenk_ereignisse" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind_id INTEGER NOT NULL REFERENCES "geschenk_kinder"(id) ON DELETE CASCADE,
      anlass TEXT NOT NULL,
      datum TEXT NOT NULL,
      jahr INTEGER NOT NULL,
      alter_zum_ereignis INTEGER,
      profil_snapshot TEXT,
      profil_bestaetigung_angefragt INTEGER DEFAULT 0,
      profil_bestaetigt INTEGER DEFAULT 0,
      recherche_gestartet INTEGER DEFAULT 0,
      recherche_abgeschlossen INTEGER DEFAULT 0,
      erstellt_am TEXT DEFAULT (datetime('now'))
    , erinnerungen_aktiv INTEGER DEFAULT 1);

CREATE TABLE IF NOT EXISTS "geschenk_geschenke" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ereignis_id INTEGER REFERENCES "geschenk_ereignisse"(id) ON DELETE SET NULL,
      kind_id INTEGER NOT NULL REFERENCES "geschenk_kinder"(id) ON DELETE CASCADE,
      titel TEXT NOT NULL,
      beschreibung TEXT,
      preis REAL,
      url TEXT,
      shop TEXT,
      status TEXT DEFAULT 'vorschlag' CHECK(status IN ('vorschlag','ausgewaehlt','bestellt','verpackt','vergeben')),
      ist_manuell INTEGER DEFAULT 0,
      quelle TEXT,
      notizen TEXT,
      erstellt_am TEXT DEFAULT (datetime('now')),
      aktualisiert_am TEXT DEFAULT (datetime('now'))
    , bild_url TEXT, ranking INTEGER, begruendung TEXT);

CREATE TABLE IF NOT EXISTS "geschenk_anlass_config" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind_id INTEGER NOT NULL REFERENCES "geschenk_kinder"(id) ON DELETE CASCADE,
      anlass TEXT NOT NULL CHECK(anlass IN ('geburtstag','ostern','weihnachten')),
      aktiv INTEGER DEFAULT 1,
      budget_min INTEGER,
      budget_max INTEGER,
      UNIQUE(kind_id, anlass)
    );

CREATE TABLE IF NOT EXISTS "geschenk_vergangene_geschenke" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind_id INTEGER NOT NULL REFERENCES "geschenk_kinder"(id) ON DELETE CASCADE,
      titel TEXT NOT NULL,
      anlass TEXT,
      jahr INTEGER,
      notizen TEXT,
      erstellt_am TEXT DEFAULT (datetime('now'))
    );

-- ── garten.db ──
CREATE TABLE IF NOT EXISTS "garten_pflanzen" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    art TEXT NOT NULL, -- baum, strauch, staude, blume, gras, hecke, kletterpflanze, bodendecker
    sorte TEXT,
    standort TEXT,
    beschreibung TEXT,
    bewaesserung TEXT DEFAULT 'hunter' CHECK(bewaesserung IN ('hunter', 'manuell')), -- Default: Hunter bewässert
    status TEXT DEFAULT 'aktiv' CHECK(status IN ('aktiv', 'entfernt')),
    bild_pfade TEXT, -- JSON Array
    erfasst_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aktualisiert_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON für zusätzliche KI-erkannte Infos
    notizen TEXT
, gts_raus INTEGER, gts_rein INTEGER, frostempfindlich INTEGER DEFAULT 0, min_temp REAL);

CREATE TABLE IF NOT EXISTS "garten_samen" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nummer TEXT NOT NULL, -- Elitas physische Nummer
    name TEXT NOT NULL,
    art TEXT, -- Gemüse, Blume, Kräuter, etc.
    sorte TEXT,
    beschreibung TEXT,
    pflanz_von INTEGER, -- Monat (1-12) ab wann pflanzen
    pflanz_bis INTEGER, -- Monat (1-12) bis wann pflanzen
    vorziehen_ab INTEGER, -- Monat ab wann vorziehen (indoor)
    ernte_von INTEGER,
    ernte_bis INTEGER,
    standort_empfehlung TEXT, -- Sonne, Halbschatten, Schatten
    abstand_cm INTEGER, -- Pflanzabstand
    tiefe_cm REAL, -- Saattiefe
    keimzeit_tage INTEGER,
    aktiv INTEGER DEFAULT 1, -- 1=aktiv, 0=inaktiv
    bild_pfade TEXT,
    erfasst_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aktualisiert_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT,
    notizen TEXT
, aussaat_2_von INTEGER, aussaat_2_bis INTEGER, ernte_2_von INTEGER, ernte_2_bis INTEGER, hersteller TEXT, bio TEXT, samenfest INTEGER DEFAULT 0, botanisch TEXT, keimtemp TEXT, keimfaehig_bis TEXT, inhalt TEXT, verwendung TEXT, typ TEXT, herkunft TEXT, besonderheiten TEXT);

CREATE TABLE IF NOT EXISTS "garten_duenger" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    marke TEXT,
    typ TEXT CHECK(typ IN ('fluessig', 'granulat', 'staebchen', 'pulver', 'organisch', 'kompost', 'sonstig')),
    beschreibung TEXT,
    geeignet_fuer TEXT,
    naehrstoffe TEXT,
    dosierung TEXT,
    intervall_wochen INTEGER,
    saison_von INTEGER,
    saison_bis INTEGER,
    vorraetig INTEGER DEFAULT 1,
    kauflink TEXT,
    bild_pfade TEXT,
    erfasst_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aktualisiert_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT,
    notizen TEXT
);

CREATE TABLE IF NOT EXISTS "garten_aufgaben" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pflanze_id INTEGER, -- NULL für allgemeine Aufgaben (z.B. Rasen)
    samen_id INTEGER,
    titel TEXT NOT NULL,
    beschreibung TEXT,
    kategorie TEXT NOT NULL, -- duengen, schneiden, giessen, pflanzen, ernten, maehen, lueften, aerifizieren, sanden, nachsaeen, bodenanalyse, ph_messen, vorziehen
    monat INTEGER NOT NULL, -- 1-12
    jahr INTEGER NOT NULL,
    erledigt INTEGER DEFAULT 0,
    erledigt_am DATETIME,
    prioritaet TEXT DEFAULT 'normal' CHECK(prioritaet IN ('niedrig', 'normal', 'hoch')),
    wiederholung TEXT, -- jaehrlich, monatlich, einmalig
    notizen TEXT, geplant_monat INTEGER, duenger_id INTEGER REFERENCES "garten_duenger"(id),
    FOREIGN KEY (pflanze_id) REFERENCES "garten_pflanzen"(id),
    FOREIGN KEY (samen_id) REFERENCES "garten_samen"(id)
);

CREATE TABLE IF NOT EXISTS "garten_pflanze_duenger" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pflanze_id INTEGER NOT NULL,
    duenger_id INTEGER,
    duenger_typ_benoetigt TEXT,
    empfohlen INTEGER DEFAULT 1,
    notizen TEXT,
    FOREIGN KEY (pflanze_id) REFERENCES "garten_pflanzen"(id) ON DELETE CASCADE,
    FOREIGN KEY (duenger_id) REFERENCES "garten_duenger"(id) ON DELETE SET NULL
);

-- ── vorratskammer.db ──
CREATE TABLE IF NOT EXISTS "vorrat_lebensmittel" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      marke TEXT,
      kategorie TEXT NOT NULL CHECK(kategorie IN ('trocken', 'kuehlschrank', 'gefrierfach')),
      menge TEXT,
      mhd TEXT,
      bild_pfad TEXT,
      status TEXT DEFAULT 'aktiv' CHECK(status IN ('aktiv', 'verbraucht')),
      restock INTEGER DEFAULT 1,
      erfasst_am TEXT DEFAULT (datetime('now')),
      verbraucht_am TEXT,
      notizen TEXT
    );

CREATE TABLE IF NOT EXISTS "vorrat_rezepte" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      titel TEXT NOT NULL,
      url TEXT,
      quelle TEXT,
      beschreibung TEXT,
      zutaten_match TEXT,
      bild_url TEXT,
      erstellt_am TEXT DEFAULT (datetime('now')),
      notizen TEXT
    );

-- ── gypsi.db ──
CREATE TABLE IF NOT EXISTS "gypsi_futter" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      marke TEXT NOT NULL,
      sorte TEXT NOT NULL,
      geschmack TEXT,
      bild_pfad TEXT,
      status TEXT DEFAULT 'mag_er' CHECK(status IN ('mag_er', 'mag_er_nicht_mehr')),
      erfasst_am TEXT DEFAULT (datetime('now')),
      status_geaendert_am TEXT,
      notizen TEXT
    );

-- ── reiniger.db ──
CREATE TABLE IF NOT EXISTS "reiniger_produkte" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      marke TEXT,
      kategorie TEXT NOT NULL DEFAULT 'allzweck',
      einsatzorte TEXT,
      geeignet_fuer TEXT,
      nicht_geeignet_fuer TEXT,
      flecken TEXT,
      pflegehinweise TEXT,
      sicherheit TEXT,
      dosierung TEXT,
      menge TEXT,
      bild_pfad TEXT,
      status TEXT DEFAULT 'aktiv' CHECK(status IN ('aktiv', 'leer', 'nachkaufen', 'entsorgt')),
      restock INTEGER DEFAULT 1,
      quelle_url TEXT,
      meta_json TEXT,
      erfasst_am TEXT DEFAULT (datetime('now')),
      aktualisiert_am TEXT,
      notizen TEXT
    , bild_mime TEXT, bild_sha256 TEXT);

CREATE TABLE IF NOT EXISTS "reiniger_anwendungen" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reiniger_id INTEGER NOT NULL REFERENCES "reiniger_produkte"(id) ON DELETE CASCADE,
      problem TEXT NOT NULL,
      material TEXT,
      anleitung TEXT NOT NULL,
      warnhinweise TEXT,
      prioritaet INTEGER DEFAULT 5,
      erstellt_am TEXT DEFAULT (datetime('now'))
    , oberflaeche TEXT, fleck_art TEXT, anwendungsfall TEXT, begruendung TEXT);

-- ── elisbooks.db ──
CREATE TABLE IF NOT EXISTS "elisbooks_books" (
    id TEXT PRIMARY KEY,
    isbn TEXT,
    title TEXT NOT NULL,
    authors TEXT NOT NULL DEFAULT '[]',
    publisher TEXT,
    published_date TEXT,
    description TEXT,
    page_count INTEGER,
    categories TEXT NOT NULL DEFAULT '[]',
    thumbnail TEXT,
    language TEXT DEFAULT 'de',
    bookshelf_id TEXT REFERENCES "elisbooks_bookshelves"(id) ON DELETE SET NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    is_on_picklist INTEGER NOT NULL DEFAULT 0,
    added_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

CREATE TABLE IF NOT EXISTS "elisbooks_bookshelves" (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    color TEXT NOT NULL DEFAULT '#3B82F6',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

CREATE TABLE IF NOT EXISTS "elisbooks_wishlist" (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    authors TEXT NOT NULL DEFAULT '[]',
    publisher TEXT,
    published_date TEXT,
    description TEXT,
    page_count INTEGER,
    categories TEXT NOT NULL DEFAULT '[]',
    thumbnail TEXT,
    isbn TEXT,
    source TEXT DEFAULT 'manual',
    added_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

CREATE TABLE IF NOT EXISTS "elisbooks_user_settings" (
    id TEXT PRIMARY KEY,
    setting_key TEXT NOT NULL UNIQUE,
    setting_value TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

-- ── ebook-wishlist.db ──
CREATE TABLE IF NOT EXISTS "ebook_wishlist" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    author TEXT,
    publisher TEXT,
    year TEXT,
    category TEXT,
    description TEXT,
    cover_url TEXT,
    isbn TEXT,
    language TEXT DEFAULT 'de',
    status TEXT DEFAULT 'gesucht',
    source_id TEXT,
    requested_by TEXT DEFAULT 'Elita',
    requested_at TEXT,
    downloaded_at TEXT,
    attempts INTEGER DEFAULT 0,
    last_attempt TEXT,
    notes TEXT,
    reviews TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

-- ── ha-voice.db ──
CREATE TABLE IF NOT EXISTS "ha_entities" (
      id INTEGER PRIMARY KEY,
      entity_id TEXT UNIQUE NOT NULL,
      domain TEXT NOT NULL,
      friendly_name TEXT,
      area_id TEXT,
      area_name TEXT,
      device_id TEXT,
      device_name TEXT,
      state TEXT,
      attributes TEXT,
      last_synced DATETIME DEFAULT CURRENT_TIMESTAMP
    , disabled BOOLEAN DEFAULT 0, discovered_at DATETIME);

CREATE TABLE IF NOT EXISTS "ha_relationships" (
      id INTEGER PRIMARY KEY,
      parent_entity_id TEXT NOT NULL,
      child_entity_id TEXT NOT NULL,
      type TEXT NOT NULL,
      auto_discovered BOOLEAN DEFAULT 1,
      manually_verified BOOLEAN DEFAULT 0,
      UNIQUE(parent_entity_id, child_entity_id, type)
    );

CREATE TABLE IF NOT EXISTS "ha_aliases" (
      id INTEGER PRIMARY KEY,
      entity_id TEXT NOT NULL,
      alias TEXT NOT NULL,
      UNIQUE(entity_id, alias)
    );

CREATE TABLE IF NOT EXISTS "ha_command_log" (
      id INTEGER PRIMARY KEY,
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
      input_text TEXT,
      matched_entity_id TEXT,
      match_score REAL,
      action TEXT,
      dependencies_triggered TEXT,
      result TEXT,
      duration_ms INTEGER,
      success BOOLEAN
    );
