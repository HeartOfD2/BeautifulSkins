-- German texts of the host. Keys are the English source texts (Locales\enUS.lua). Packs keep their own tables and
-- fall back to this one for shared words.
local _, ns = ...

ns.locales.deDE = {
    ["%s - options"] = "%s – Optionen",
    ["%s eui - the options in EllesmereUI"] = "%s eui – die Optionen in EllesmereUI",
    ["%s help lists all commands."] = "%s help zeigt alle Befehle.",
    ["%s minimap - show or hide the minimap button"] = "%s minimap – Minikartenknopf zeigen oder verbergen",
    ["%s options - our own options window"] = "%s options – unser eigenes Optionsfenster",
    ["%s reset - reset look and language"] = "%s reset – Aussehen und Sprache zurücksetzen",
    ["%s status - state of every skin"] = "%s status – Zustand aller Skins",
    ["%s: the former addon %s is still active. Switch it off in the addon list and /reload; its settings are taken over."] =
        "%s: Das frühere Addon %s ist noch aktiv. Schalte es in der Addon-Liste aus und lade mit /reload neu; seine Einstellungen werden übernommen.",
    ["Accent"] = "Akzent",
    ["Accent as text"] = "Akzent als Text",
    ["Accent color"] = "Akzentfarbe",
    ["active"] = "aktiv",
    ["addon not installed"] = "Addon nicht installiert",
    ["Adds our section to the EllesmereUI options window; the slash command and the minimap button open it there. Off: our own window. Takes effect after a reload."] =
        "Fügt unseren Bereich ins EllesmereUI-Optionsfenster ein; Befehl und Minikartenknopf öffnen ihn dort. Aus: unser eigenes Fenster. Wirkt nach einem Neuladen.",
    ["All options are in our own window (or in the EllesmereUI options when the integration is on). Command: %s"] =
        "Alle Optionen stehen in unserem eigenen Fenster (oder in den EllesmereUI-Optionen, wenn die Einbindung an ist). Befehl: %s",
    ["APPEARANCE"] = "AUSSEHEN",
    ["Appearance"] = "Aussehen",
    ["Attune classic"] = "Attune klassisch",
    ["Automatic"] = "Automatisch",
    ["Automatic uses the EllesmereUI language when it is installed, else the language of the game."] =
        "Automatisch nutzt die EllesmereUI-Sprache, wenn es installiert ist, sonst die Sprache des Spiels.",
    ["Automatic uses the language of the game."] = "Automatisch nutzt die Sprache des Spiels.",
    ["Borders"] = "Rahmen",
    ["Buttons"] = "Knöpfe",
    ["Class color"] = "Klassenfarbe",
    ["Classic"] = "Klassisch",
    ["Click a color to use it as the accent."] = "Klicke eine Farbe an, um sie als Akzent zu nutzen.",
    ["Close"] = "Schließen",
    ["Code ready: Ctrl+C copies it. Import pastes it on another account or for a friend."] =
        "Code bereit: Strg+C kopiert ihn. Mit „Importieren“ fügst du ihn auf einem anderen Account oder bei Freunden ein.",
    ["COLORS"] = "FARBEN",
    ["COMMANDS"] = "BEFEHLE",
    ["Commands:"] = "Befehle:",
    ["CONTRAST"] = "KONTRAST",
    ["Copies the colors of the theme in use into a new own theme and switches to it."] =
        "Kopiert die Farben des aktiven Themes in ein neues eigenes Theme und schaltet darauf um.",
    ["Dark"] = "Dunkel",
    ["Dark or light: decides how hover and tracks are shaded."] =
        "Dunkel oder hell: bestimmt, wie Hover und Leisten schattiert werden.",
    ["Delete"] = "Löschen",
    ["Drag: move along the minimap"] = "Ziehen: am Rand der Minikarte verschieben",
    ["Each pack skins one addon or a group of addons. A pack whose addon is not installed stays asleep. Changes take effect after a reload."] =
        "Jedes Paket gestaltet ein Addon oder eine Gruppe von Addons. Ein Paket, dessen Addon fehlt, bleibt still. Änderungen wirken nach einem Neuladen.",
    ["EllesmereUI accent"] = "EllesmereUI-Akzent",
    ["EllesmereUI font"] = "EllesmereUI-Schrift",
    ["EllesmereUI found: accent, font and language can follow it."] =
        "EllesmereUI gefunden: Akzent, Schrift und Sprache können ihm folgen.",
    ["EllesmereUI is missing or too old (no plugin API)."] =
        "EllesmereUI fehlt oder ist zu alt (keine Plugin-Schnittstelle).",
    ["EllesmereUI is not loaded. %s options opens our own window."] =
        "EllesmereUI ist nicht geladen. %s options öffnet unser eigenes Fenster.",
    ["EllesmereUI not found: own window and own look."] =
        "EllesmereUI nicht gefunden: eigenes Fenster und eigenes Aussehen.",
    ["Ember"] = "Glut",
    ["Emerald"] = "Smaragd",
    ["Export"] = "Exportieren",
    ["failed"] = "fehlgeschlagen",
    ["Font"] = "Schrift",
    ["Font of all our texts."] = "Schrift aller unserer Texte.",
    ["Font of all our texts. \"EllesmereUI font\" follows the font set in EllesmereUI (only while it is installed and enabled)."] =
        "Schrift aller unserer Texte. „EllesmereUI-Schrift“ folgt der in EllesmereUI gewählten Schrift (nur solange es installiert und aktiv ist).",
    ["Frost"] = "Frost",
    ["Game font"] = "Spielschrift",
    ["GearQuest, SkillUp, Whisper, Waypoint"] = "GearQuest, SkillUp, Whisper, Waypoint",
    ["General"] = "Allgemein",
    ["good"] = "gut",
    ["Graphite"] = "Graphit",
    ["Header area"] = "Kopfbereich",
    ["Headings"] = "Überschriften",
    ["Headings on the header area"] = "Überschriften im Kopfbereich",
    ["High contrast"] = "Hoher Kontrast",
    ["Highlight color of every theme and of every skin: headings, lines, arrows, buttons and switches."] =
        "Hervorhebungsfarbe aller Themes und Skins: Überschriften, Linien, Pfeile, Knöpfe und Schalter.",
    ["Import"] = "Importieren",
    ["Imported as a new own theme."] = "Als neues eigenes Theme importiert.",
    ["Info"] = "Info",
    ["Input fields"] = "Eingabefelder",
    ["Integrate into EllesmereUI"] = "In EllesmereUI einbinden",
    ["INTEGRATION"] = "EINBINDUNG",
    ["Kind"] = "Art",
    ["Language"] = "Sprache",
    ["LANGUAGE"] = "SPRACHE",
    ["Left-click opens the options, right-click the quick actions. Drag it to move it along the minimap."] =
        "Linksklick öffnet die Optionen, Rechtsklick die Schnellaktionen. Ziehen verschiebt ihn am Rand der Minikarte.",
    ["Left-click: options"] = "Linksklick: Optionen",
    ["Light"] = "Hell",
    ["Look of our own windows and of the skinned windows that follow a theme (Attune)."] =
        "Aussehen unserer eigenen Fenster und der gestalteten Fenster, die einem Theme folgen (Attune).",
    ["Look, language, packs and information."] = "Aussehen, Sprache, Pakete und Informationen.",
    ["Make your own theme from any theme, change every color and share it as a code. The theme you edit is in use, so every window shows the change at once."] =
        "Mach aus jedem Theme dein eigenes, ändere jede Farbe und teile es als Code. Das bearbeitete Theme ist aktiv, so zeigt jedes Fenster die Änderung sofort.",
    ["Midnight"] = "Mitternacht",
    ["Minimap button hidden. %s minimap shows it again."] =
        "Minikartenknopf verborgen. %s minimap zeigt ihn wieder.",
    ["Minimap button shown."] = "Minikarten-Knopf eingeblendet.",
    ["Modern"] = "Modern",
    ["Name"] = "Name",
    ["New from the current theme"] = "Neu aus aktuellem Theme",
    ["No"] = "Nein",
    ["No own theme yet. \"New from the current theme\" copies the theme in use; then change any color."] =
        "Noch kein eigenes Theme. „Neu aus aktuellem Theme“ kopiert das aktive Theme, danach kannst du jede Farbe ändern.",
    ["Nord"] = "Nord",
    ["not part of this installation"] = "nicht Teil dieser Installation",
    ["off"] = "aus",
    ["Open in EllesmereUI"] = "In EllesmereUI öffnen",
    ["Open the options"] = "Optionen öffnen",
    ["Opens the color picker. The chosen color becomes the accent."] =
        "Öffnet die Farbauswahl. Die gewählte Farbe wird zum Akzent.",
    ["Options"] = "Optionen",
    ["Own color"] = "Eigene Farbe",
    ["Own theme"] = "Eigenes Theme",
    ["OWN THEMES"] = "EIGENE THEMES",
    ["Parchment"] = "Pergament",
    ["Paste a theme code here"] = "Theme-Code hier einfügen",
    ["Pick any color"] = "Beliebige Farbe wählen",
    ["Print the state to the chat"] = "Zustand im Chat ausgeben",
    ["Reload now"] = "Jetzt neu laden",
    ["Repeat within 10 seconds to confirm."] = "Zum Bestätigen innerhalb von 10 Sekunden wiederholen.",
    ["RESET"] = "ZURÜCKSETZEN",
    ["Reset look and language"] = "Aussehen und Sprache zurücksetzen",
    ["Reset the look, language and window of %s to the defaults? The interface reloads."] =
        "Aussehen, Sprache und Fenster von %s auf die Standardwerte zurücksetzen? Die Oberfläche wird neu geladen.",
    ["Right-click: quick actions"] = "Rechtsklick: Schnellaktionen",
    ["Rosé"] = "Rosé",
    ["runs in BeautifulSkins"] = "läuft in BeautifulSkins",
    ["Secondary text"] = "Nebentext",
    ["Secondary text on the window"] = "Nebentext auf dem Fenster",
    ["SHARE"] = "TEILEN",
    ["Show the minimap button"] = "Minikarten-Knopf anzeigen",
    ["SKIN PACKS"] = "SKIN-PAKETE",
    ["Standard"] = "Standard",
    ["Sure?"] = "Sicher?",
    ["Takes effect after /reload."] = "Wirkt nach /reload.",
    ["Text"] = "Text",
    ["Text on buttons"] = "Text auf Knöpfen",
    ["Text on the accent"] = "Text auf dem Akzent",
    ["Text on the window"] = "Text auf dem Fenster",
    ["Text should reach 4.5 : 1 to stay easy to read."] =
        "Text sollte 4,5 : 1 erreichen, damit er gut lesbar bleibt.",
    ["That is no theme code (it starts with BT1:)."] = "Das ist kein Theme-Code (er beginnt mit BT1:).",
    ["The code is damaged or incomplete."] = "Der Code ist beschädigt oder unvollständig.",
    ["The color picker is not available in this client."] =
        "Die Farbauswahl ist in diesem Client nicht verfügbar.",
    ["The EllesmereUI integration changes after a reload (/reload)."] =
        "Die EllesmereUI-Einbindung ändert sich nach dem Neuladen (/reload).",
    ["The EllesmereUI integration is off. Turn it on under General, then /reload."] =
        "Die EllesmereUI-Einbindung ist aus. Unter Allgemein einschalten, dann /reload.",
    ["The EllesmereUI section is not active (%s). Try /reload."] =
        "Der EllesmereUI-Abschnitt ist nicht aktiv (%s). Versuche /reload.",
    ["The EllesmereUI window cannot be opened in combat. %s options works."] =
        "Das EllesmereUI-Fenster lässt sich im Kampf nicht öffnen. %s options funktioniert.",
    ["the former addon is still active: switch it off and /reload"] =
        "das frühere Addon ist noch aktiv: ausschalten und /reload",
    ["The language changes after a reload (/reload)."] =
        "Die Sprache ändert sich nach einem Neuladen (/reload).",
    ["The quick brown fox jumps over the lazy dog. 0123456789"] =
        "Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich. 0123456789",
    ["Theme"] = "Theme",
    ["Theme default"] = "Theme-Standard",
    ["Theme editor"] = "Theme-Editor",
    ["Theme, font, accent, language and window position back to the defaults, then the interface reloads. The options of the skins stay."] =
        "Theme, Schrift, Akzent, Sprache und Fensterposition zurück auf Standard, danach lädt die Oberfläche neu. Die Optionen der Skins bleiben.",
    ["too low"] = "zu niedrig",
    ["Unknown command."] = "Unbekannter Befehl.",
    ["Unofficial skins. Not affiliated with the authors of the skinned addons or of EllesmereUI."] =
        "Inoffizielle Skins. Nicht verbunden mit den Autoren der gestalteten Addons oder von EllesmereUI.",
    ["Used while the accent color is set to \"Theme default\"."] =
        "Gilt, solange die Akzentfarbe auf „Theme-Standard“ steht.",
    ["VERSIONS"] = "VERSIONEN",
    ["waiting"] = "wartet",
    ["Warning"] = "Warnung",
    ["Warning on buttons"] = "Warnung auf Knöpfen",
    ["Window"] = "Fenster",
    ["Without EllesmereUI every option lives in this window. With EllesmereUI installed the same pages can also appear in its options window."] =
        "Ohne EllesmereUI stehen alle Optionen in diesem Fenster. Mit EllesmereUI können dieselben Seiten auch in dessen Optionsfenster erscheinen.",
    ["Yes"] = "Ja",
}
