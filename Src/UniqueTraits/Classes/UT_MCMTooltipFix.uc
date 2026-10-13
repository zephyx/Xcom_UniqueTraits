//---------------------------------------------------------------------------------------
//  FILE:   UT_MCMTooltipFix.uc
//  PURPOSE: Works around a defect of Mod Config Menu (2026-10-12: the hover tooltips of a mod's page only appear from the SECOND time its tab is selected,
//           for every mod). The first time a tab is selected MCM_SettingsPanelFacade.Show() only builds the panel (CreateUi) and the
//           rows are created with their tooltip, but each facade then calls uiInstance.SetEditable(...), whose SetDisabled (UIMechaListItem) calls BG.RemoveTooltip()
//           when there is no "disabled" reason. MCM's own re-application (AfterParentPageDisplayed, from the panel's Show) only happens on the next selection.
//           MCM sends no event when a page is displayed, so this panel LOOKS: POLL_SECONDS apart it walks the options screen and, for EVERY row that is an MCM setting
//           (ours and the other mods), has its background initialised and no tooltip any more, puts back the text
//           MCM still holds (GetHoverTooltip; an empty text is left alone, so a row meant to have no tooltip stays without).
//           It changes nothing in MCM and only reads vanilla UI fields (UIPanel.bHasTooltip / bIsInited, UIMechaListItem.BG): if MCM's structure were different it would
//           simply find nothing. Spawned by UniqueTraits_MCMScreen.OnInit on MCM's options screen only (ini switch MCM_TOOLTIP_FIX_ENABLED), so it never exists without MCM.
//           The panel tree has a CYCLE (MCM_OptionsScreen is one of its own children).
//---------------------------------------------------------------------------------------
class UT_MCMTooltipFix extends UIPanel;

const POLL_SECONDS = 0.25;
const MAX_DEPTH = 12;
const MAX_SCAN_LOGS = 3;
const MAX_FIX_LOGS = 20;

var float LastScanTime;
var int RowsSeen, SettingsSeen, FixesThisScan, ScanLogs, FixLogs;
var array<UIPanel> Visited;   // the panels already walked during this scan

simulated function UT_MCMTooltipFix InitFix()
{
	InitPanel();

	return self;
}

simulated event Tick(float DeltaTime)
{
	// Real time, not DeltaTime: when MCM is opened from a game (pause menu) the world is paused.
	if (WorldInfo.RealTimeSeconds - LastScanTime < POLL_SECONDS)
		return;

	LastScanTime = WorldInfo.RealTimeSeconds;
	RowsSeen = 0;
	SettingsSeen = 0;
	FixesThisScan = 0;
	Visited.Length = 0;
	FixTooltips(Screen, 0);

	// To measure the cost: the first scans, and the scans that put tooltips back (the first ones only).
	if (ScanLogs < MAX_SCAN_LOGS || (FixesThisScan > 0 && FixLogs < MAX_FIX_LOGS))
	{
		++ScanLogs;
		++FixLogs;
		`log("UniqueTraits : MCM tooltip fix -> scan: panels walked" @ Visited.Length $ ", rows" @ RowsSeen $ ", MCM settings" @ SettingsSeen $ ", tooltips put back" @ FixesThisScan,, 'UniqueTraits');
	}
}

// Depth-first walk of the panels under Panel. A settings row is a UIMechaListItem (MCM_SettingBase) that can be seen as an MCM_API_Setting; nothing below a row matters.
simulated function FixTooltips(UIPanel Panel, int Depth)
{
	local UIMechaListItem Row;
	local MCM_API_Setting Setting;
	local string TooltipText;
	local int i;

	if (Panel == none || Panel.bIsRemoved || Depth > MAX_DEPTH || Visited.Find(Panel) != INDEX_NONE)
		return;

	Visited.AddItem(Panel);

	Row = UIMechaListItem(Panel);
	if (Row != none)
	{
		++RowsSeen;
		Setting = MCM_API_Setting(Panel);
		if (Setting == none || Row.BG == none)
			return;

		++SettingsSeen;
		if (Row.BG.bIsInited && !Row.BG.bHasTooltip)
		{
			TooltipText = Setting.GetHoverTooltip();
			if (TooltipText != "")
			{
				Setting.SetHoverTooltip(TooltipText);
				++FixesThisScan;
			}
		}

		return;
	}

	for (i = 0; i < Panel.ChildPanels.Length; ++i)
		FixTooltips(Panel.ChildPanels[i], Depth + 1);
}

defaultproperties
{
	// MCM opened from a game pauses the world and an Actor does not tick while it is paused unless it asks to (the base game's UIPauseMenu, UITooltipMgr and UIOptionsPCScreen do)
	bAlwaysTick = true
}
