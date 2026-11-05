-- Package description: which skin packs this build ships and how the host presents itself. The development checkout
-- holds the BeautifulSkins suite; tools/make_release.py writes a different file for the single packages
-- (BeautifulAttune, BeautifulRestedXP). Nothing else in the host names a package.
local _, ns = ...

ns.PACKAGE = {
    title = "BeautifulSkins",
    db = "BeautifulSkinsDB",          -- SavedVariables of the host (TOC)
    slash = { "/bskins", "/beautifulskins" },
    color = "0cd29d",                 -- chat prefix
    pluginLabel = "Beautiful Skins",  -- section in the EllesmereUI options window (must not start with "EUI")
    defaultTheme = "midnight",
    -- Skin packs, each a LoadOnDemand addon next to the host. requires = the skinned addon (nil: the pack checks
    -- its targets itself).
    packs = {
        { key = "Extras", addon = "BeautifulSkins_Extras", title = "GearQuest, SkillUp, Whisper, Waypoint" },
        { key = "Attune", addon = "BeautifulSkins_Attune", title = "Attune", requires = "Attune",
          imports = { addon = "BeautifulAttune", db = "BeautifulAttuneDB" } },
        { key = "RestedXP", addon = "BeautifulSkins_RestedXP", title = "RestedXP", requires = "RXPGuides",
          imports = { addon = "EUI_RestedXP_Skin", db = "EUIRestedXPSkinDB" } },
    },
    -- imports = the former single addon of a pack: while it still runs the pack stays off (no double skin), and a
    -- pack with empty SavedVariables takes over its settings (ns.ImportedSettings).
    -- Pack that takes over db.legacy (settings of BeautifulSkins 0.1, before the host existed).
    legacyPack = "Extras",
    -- Another host that already ships the same packs; a single package stays quiet next to it.
    yieldTo = nil,
}
