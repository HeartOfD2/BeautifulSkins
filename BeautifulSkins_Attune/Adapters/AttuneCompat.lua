-- Contract with Attune: every Attune name the skin relies on, grouped by capability.
-- Only this file and Adapters/Attune.lua may know Attune names. tools/attune_contract.py reads the entries below
-- (one table per line, keep the format) and checks them against a new Attune source tree.
--
-- kind:  function = global function        frame = named frame (global)
--        global   = any global value        field = dotted path; the root is a global or an @alias
-- when:  load   = present after login       window = present after Attune's window was opened once
--        lazy   = created on demand (shown as "not created yet" until then, never blocks a module)
-- Names ending in "*" are frame-name prefixes (one frame per step); they are checked offline only.
-- @aliases are resolved by the adapter: @Tree = the list widget, @Graph = the chain scroll widget.
-- nilable = the field may legitimately be nil (a saved option that was never set).
local _, ns = ...

local Compat = {}
ns.AttuneCompat = Compat

Compat.testedVersions = { "16001-32", "16001-34", "16001-35", "16001-37" }

Compat.contract = {
    -- data and saved variables
    { cap = "Data", kind = "global", name = "Attune_Data", when = "load" },
    { cap = "Data", kind = "field", name = "Attune_Data.attunes", when = "load" },
    { cap = "Data", kind = "field", name = "Attune_Data.steps", when = "load" },
    { cap = "StepIndex", kind = "field", name = "Attune_Data.attuneById", when = "load" },
    { cap = "StepIndex", kind = "field", name = "Attune_Data.stepsByAttune", when = "load" },
    { cap = "PatchStep", kind = "function", name = "showPatchStep", when = "load" },
    { cap = "Lang", kind = "global", name = "AttuneLang", when = "load" },
    { cap = "DB", kind = "global", name = "Attune_DB", when = "load" },
    { cap = "DB", kind = "field", name = "Attune_DB.toons", when = "load" },
    { cap = "DB", kind = "field", name = "Attune_DB.showAllClassQuests", when = "load", nilable = true },
    { cap = "DB", kind = "field", name = "Attune_DB.showDeprecatedAttunes", when = "load", nilable = true },
    { cap = "DB", kind = "field", name = "Attune_DB.archiveCompleted", when = "load", nilable = true },
    { cap = "StoredZoom", kind = "field", name = "Attune_DB.zoom", when = "load" },
    -- window life cycle and list
    { cap = "Slash", kind = "function", name = "Attune_SlashCommandHandler", when = "load" },
    -- Attune's second window ("Attune: Next", a list with the next step of every attunement) and its own options
    { cap = "NextWindow", kind = "function", name = "Attune_NextFrameUpdate", when = "load" },
    { cap = "NextWindow", kind = "field", name = "Attune_DB.showNextSteps", when = "load", nilable = true },
    { cap = "NextWindow", kind = "field", name = "AttuneLang.NextSteps_TITLE", when = "load" },
    { cap = "NextWindow", kind = "function", name = "Attune_NextFrameLayout", when = "load" },
    { cap = "NextWindow", kind = "global", name = "AttuneNextFrame", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.scroll", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.content", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.empty", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.grip", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.minBtn", when = "lazy" },
    { cap = "NextWindow", kind = "field", name = "@Next.rows", when = "lazy" },
    { cap = "AttuneOptions", kind = "field", name = "@Broker.OnClick", when = "lazy" },
    -- the "Will not do" checkbox on the chain and the counts Attune writes straight on the cards of a character trial
    { cap = "SkipCheck", kind = "function", name = "Attune_CreateSkipCheck", when = "load" },
    { cap = "SkipCheck", kind = "function", name = "Attune_UpdateSkipCheck", when = "load" },
    { cap = "SkipCheck", kind = "global", name = "AttuneSkipCheck", when = "lazy" },
    { cap = "StatLabels", kind = "function", name = "Attune_RefreshOpenStatLabels", when = "load" },
    { cap = "Frame", kind = "function", name = "Attune_Frame", when = "load" },
    { cap = "ToggleView", kind = "function", name = "Attune_ToggleView", when = "load" },
    { cap = "Portrait", kind = "function", name = "Attune_UpdateWindowPortrait", when = "load" },
    { cap = "Path", kind = "function", name = "Attune_PathForAttune", when = "load" },
    { cap = "LastViewed", kind = "function", name = "Attune_GetLastViewed", when = "load" },
    { cap = "ReloadTree", kind = "function", name = "Attune_ReloadAttuneTree", when = "load" },
    { cap = "IconView", kind = "function", name = "Attune_SetIconView", when = "load" },
    { cap = "IconView", kind = "global", name = "attunelocal_viewToggle", when = "lazy" },
    { cap = "IconView", kind = "global", name = "attunelocal_iconView", when = "lazy" },
    { cap = "MainFrame", kind = "frame", name = "Attune_MainFrame", when = "window" },
    { cap = "MainFrame", kind = "field", name = "Attune_MainFrame.obj", when = "window" },
    { cap = "Chrome", kind = "frame", name = "AttuneBronzeChrome", when = "window" },
    { cap = "Chrome", kind = "field", name = "AttuneBronzeChrome.CloseButton", when = "window" },
    { cap = "Survey", kind = "frame", name = "Attune_SurveyMenuFrame", when = "window" },
    { cap = "ResultsButton", kind = "frame", name = "GuildButton", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.content", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.statustext", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.titletext", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.sizer_se", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.sizer_s", when = "window" },
    { cap = "WindowParts", kind = "field", name = "@Main.sizer_e", when = "window" },
    { cap = "Texts", kind = "field", name = "AttuneLang.Survey", when = "load" },
    { cap = "Texts", kind = "field", name = "AttuneLang.Results", when = "load" },
    { cap = "Texts", kind = "field", name = "AttuneLang.Attunes", when = "load" },
    { cap = "Tree", kind = "field", name = "@Tree.SelectByPath", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.RefreshTree", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.OnRelease", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.treeframe", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.border", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.buttons", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.dragger", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.scrollbar", when = "window" },
    { cap = "Tree", kind = "field", name = "@Tree.localstatus", when = "window" },
    -- chain graph and zoom
    { cap = "Select", kind = "function", name = "Attune_Select", when = "load" },
    { cap = "CreateNode", kind = "function", name = "Attune_CreateNode", when = "load" },
    { cap = "SideFeeder", kind = "function", name = "Attune_DrawSideFeeder", when = "load" },
    { cap = "GraphRoot", kind = "frame", name = "Attune_GraphRoot", when = "window" },
    { cap = "GraphScroll", kind = "field", name = "@Graph.scrollframe", when = "window" },
    { cap = "GraphScroll", kind = "field", name = "@Graph.content", when = "window" },
    { cap = "GraphScroll", kind = "field", name = "@Graph.children", when = "window" },
    { cap = "GraphScroll", kind = "field", name = "@Graph.scrollbar", when = "window" },
    { cap = "GraphScroll", kind = "field", name = "@Graph.DoLayout", when = "window" },
    { cap = "Pan", kind = "function", name = "Attune_ApplyGraphPan", when = "load" },
    { cap = "Pan", kind = "function", name = "Attune_UpdateGraphPanLimits", when = "load" },
    { cap = "Nodes", kind = "frame", name = "Attune_Node_*", when = "window" },
    { cap = "Nodes", kind = "frame", name = "Attune_Icon_*", when = "window" },
    { cap = "Nodes", kind = "frame", name = "Attune_Title_*", when = "window" },
    { cap = "Nodes", kind = "frame", name = "Attune_Type_*", when = "window" },
    { cap = "Nodes", kind = "frame", name = "Attune_Notif_*", when = "window" },
    { cap = "Nodes", kind = "frame", name = "Attune_NotifText_*", when = "window" },
    { cap = "Lines", kind = "frame", name = "Attune_Line1_*", when = "window" },
    { cap = "Lines", kind = "frame", name = "Attune_Line2_*", when = "window" },
    { cap = "Lines", kind = "frame", name = "Attune_Line3_*", when = "window" },
    { cap = "Lines", kind = "frame", name = "Attune_SpacerFill_*", when = "window" },
    { cap = "Lines", kind = "frame", name = "Attune_SideFeeder_*", when = "window" },
    { cap = "OrMarks", kind = "frame", name = "Attune_OrLabel_*", when = "window" },
    { cap = "SideBox", kind = "frame", name = "Attune_SideBox", when = "lazy" },
    { cap = "SideBox", kind = "frame", name = "Attune_SideBoxTitle", when = "lazy" },
    { cap = "Zoom", kind = "function", name = "Attune_ApplyGraphZoom", when = "load" },
    { cap = "Zoom", kind = "function", name = "Attune_CreateZoomSlider", when = "load" },
    { cap = "Zoom", kind = "function", name = "Attune_ReleaseZoomSlider", when = "load" },
    -- quest details, rewards, giver hint, results
    { cap = "QuestDetail", kind = "function", name = "Attune_ShowQuestDetail", when = "load" },
    { cap = "QuestDetail", kind = "function", name = "Attune_HideQuestDetail", when = "load" },
    { cap = "QuestDetail", kind = "frame", name = "AttuneQuestDetail", when = "lazy" },
    { cap = "QuestRewards", kind = "function", name = "Attune_ShowQuestRewards", when = "load" },
    { cap = "QuestRewards", kind = "frame", name = "AttuneQuestRewardFrame", when = "lazy" },
    { cap = "GiverTip", kind = "frame", name = "AttuneGiverTip", when = "lazy" },
    { cap = "Results", kind = "function", name = "Attune_ShowResultList", when = "load" },
    { cap = "Results", kind = "function", name = "Attune_EnsureResultHolder", when = "load" },
    { cap = "Results", kind = "function", name = "Attune_ResultRowHeight", when = "load" },
    { cap = "Results", kind = "function", name = "Attune_UpdateResultScroll", when = "load" },
    { cap = "Results", kind = "global", name = "attunelocal_resultHolder", when = "lazy" },
}
