# Changelog

## 0.2.9 (2026-11-07)

- With Waypoint UI: while the BeautifulRestedXP arrow is on, Waypoint UI's "RestedXP support" is switched off (and
  back on when you switch our arrow off). It made a navigation of its own to every RestedXP target, and while it was
  tracked ShortestPathForever handed its bends to Waypoint UI, where they landed in the map's corner: journeys showed
  no bends after a reload until that waypoint was clicked away.
- ShortestPathForever 1.22.46 and later: its own gold goal pin and, since 1.22.48, its numbered markers for stops
  and turns (world map, minimap, compass, on screen) are in the accent colour again, and with OpenMap the waypoint
  marker of the route's next bend too (your own waypoints keep their gold).
- Switching the target (RestedXP step, your own journey, a GearQuest hunt) first clears a waypoint that was still on
  the map. Such a leftover waypoint made ShortestPathForever skip the bends, and the arrow pointed at the end.

## 0.2.8 (2026-11-07)

- OpenMap fix: with map pins off, Ctrl-click on the map now does nothing at all. Before, it set the game's waypoint or
  planned a ShortestPathForever journey, and during a journey it could leave a stray waypoint behind and break the
  next Shift-click.

## 0.2.7 (2026-11-07)

- New: OpenMap. The OpenMap button on the map opens a new menu in the BeautifulSkins look: search, one row of quick
  buttons and the settings in eight pages (On the map, Dungeons, Townsfolk, Look, Up close, Window and buttons, Pins and
  quill, Other addons) with switches, sliders and choices instead of one long list of tick boxes. The same pages are in
  the BeautifulSkins options (More skins > OpenMap). Switch it off under More skins > Skins.
- OpenMap's map pins and its quill can each be switched off completely (More skins > Skins, or Pins and quill in the
  menu). It works at once; switching on again brings back your pins, drawings and buttons. With pins off, Ctrl-click on
  the map sets nothing; with ShortestPathForever it plans a journey there, as Shift-click does.
- The OpenMap menu has the language choice too (Window and buttons), with a button to reload.

## 0.2.6 (2026-11-07)

- RestedXP fix: after you set your own waypoint (Shift-click on the map), the arrow pointed at the RestedXP target while the
  distance and name were those of your waypoint. ShortestPathForever first gives back the waypoint that stood before
  the guide's journey; the arrow now follows only waypoints ShortestPathForever set itself and otherwise points
  straight at your target until the route's first bend is placed. This also applies with "Arrow to the next map marker".

## 0.2.5 (2026-11-06)

- RestedXP: new option "Show the BeautifulRestedXP arrow" (Navigation > Arrow), on by default. Switch it off when another
  addon such as TomTom shows the way. GearQuest hunts then use GearQuest's own arrow.
- ShortestPathForever's own arrow now stays invisible while this arrow is on, so you always see one arrow. "Show direction
  arrow" in ShortestPathForever stays on, because it gives this arrow the bends of the route; switching this arrow off
  puts your ShortestPathForever setting back. The option "Hide the ShortestPathForever arrow" is gone.

## 0.2.4 (2026-11-06)

- ShortestPathForever: the journey and its markers now follow the accent colour everywhere: the goal pin and ring on
  the minimap, the route, stop buttons and numbers on the world map, the boat and zeppelin lines and the glow of a
  hovered dock, the flight master's tracked mark, and the compass and screen pins. Changing the accent repaints all of
  it at once. Transport and flight master icons keep their look.
- The option is now called "Route and markers in the accent colour" (RestedXP options, Navigation > Map, section Map).

## 0.2.3 (2026-11-06)

- Tested with Attune 16001-37.
- Attune's new "Will not do" checkbox at the bottom right of the chain has the same flat look, and attunements you set
  aside are greyed in the list.
- Attune's Character Progression chains: the cards show the name of each goal, and their counts update while the chain
  is open.
- New: ShortestPathForever's route on the minimap takes the accent colour (RestedXP options, Navigation > Map; on by
  default, off gives the route its own colours back).
- Fix: a character without a second name is recognised by the Attune skin.

## 0.2.2 (2026-11-05)

- Fix: with ShortestPathForever following a RestedXP guide, the target no longer switches on and off several times a
  second in a looping kill area. RestedXP's own arrow is now made invisible instead of being switched off through its
  "Hide waypoint arrow" setting, which disturbed the guide's looping waypoints. The setting is cleaned up on the first
  start.

## 0.2.1 (2026-11-05)

- Fix: the RestedXP guide window no longer jumps when you let go of its size grip. The top edge stays where it is,
  the width stays as dragged, and the height goes back to the height of the rows.

## 0.2.0 (2026-11-05)

BeautifulSkins now also contains the former addons **BeautifulAttune** and **EUI RestedXP Skin**. Update by replacing the
folders; the four folders of the package belong together.

- **Attune** and **RestedXP Guides** skins are part of BeautifulSkins (their settings are taken over on the first
  start). Attune's second window "Attune: Next" is skinned as well, and the Attune header has two new buttons: one
  switches that window on and off, one opens Attune's own options. Tested with Attune 16001-35.
- **Thirteen themes** instead of seven: Standard, Graphite, Midnight, Frost, Nord, Emerald, Ember, High contrast, Light,
  Rosé, Parchment, Classic and, with EllesmereUI, EllesmereUI. A theme gallery shows them side by side.
- **Theme editor**: make your own themes from any theme, pick every colour, see the contrast live, and share a theme
  as a code (export / import).
- Every theme was checked for readable contrast (WCAG 4.5:1); a class or own accent colour is adjusted where it is
  used as text.
- **One arrow for GearQuest Forever and RestedXP**: GearQuest hunts run as ShortestPathForever journeys on the arrow of
  the RestedXP skin; a switch (guide window, tracker, Shift-click on the arrow, key bindings, `/brxp target`) goes back
  and forth between the guide's target and your own journey. While that arrow runs, GearQuest's own arrow options are off.
- New arrow option **Arrow to the next map marker** (the marker tracked right now, as ShortestPathForever's own arrow),
  and the arrow shows the distance to the next bend while the goal is on another continent.
- Own options window when EllesmereUI is not installed: themes, bundled fonts, accent colours, minimap button and quick
  actions; with EllesmereUI the same pages appear in its options window (switchable).
- The skins are separate folders that BeautifulSkins loads; each one can be switched off under General.
- Fixes: dragging the Attune list's scroll bar follows the mouse; the RestedXP guide window keeps its place when its size
  grip is dragged.

## 0.1.0 (beta)

First public version, built for WoW: Forever (Interface 16001). Tested with GearQuest Forever 1.0.4, SkillUp Forever
0.18.13, Whisper Messenger 2.1.0, Waypoint UI 1.7.4 and EllesmereUI 9.6.1.

- GearQuest Forever: tracker in the EllesmereUI quest tracker look, or as a section of the Forever tracker column;
  arrow with four styles, three colour modes, size, yards or metres, distance and hunt name, above the tracker or free
  and movable; flat main window and settings, simulator and filter pages; flat upgrade bar, toast and guide bubble.
- SkillUp Forever: tracked reagents section in the EllesmereUI quest tracker look.
- Whisper Messenger: dark preset, flat frame and EllesmereUI font; chat button in the EllesmereUI chat sidebar (or a
  corner of the chat) with the number of unread whispers and a glow; Whisper Messenger's own icons can be hidden.
- Waypoint UI: accent colour for waypoint, beam, pinpoint and navigator, EllesmereUI font for the texts.
- Options in EllesmereUI's options window or in the game menu; accent from EllesmereUI, class colour or your own colour;
  English and German.
