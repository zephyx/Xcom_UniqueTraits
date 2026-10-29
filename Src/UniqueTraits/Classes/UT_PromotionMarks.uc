//---------------------------------------------------------------------------------------
//  FILE:   UT_PromotionMarks.uc
//  PURPOSE: Marks the "evolution" abilities of Someone different (UT_Trait_SomeoneDifferent) on the promotion screen with a green DIAMOND BEHIND THE ICON,
//           for a soldier who holds the trait and has mutated, and for him only. The diamond is a filled UIBGBox as large
//           as the icon's square, turned by 45 degrees, so that its corners stick out of the round icon.
//           A child of an icon is drawn above the icon, so the diamonds are children of the COLUMN (siblings of the icons, placed from the icons'
//           own flash position, MC.GetNum("_x"/"_y")) and, once created, the column's icons are moved back to the top (UIPanel.MoveToHighestDepth):
//           they then cover the diamonds. The diamonds of a column are created the first time a mutated holder needs them: any other soldier costs nothing.
//           The evolution of a column is the row UT_Trait_SomeoneDifferent.GetEvolutionRow gives; it is located on screen through the column's
//           AbilityNames (so it follows the vertical scroll of Community Promotion Screen). The screen has no event when it refreshes its icons (the
//           flash side resets them on every PopulateData), so the panel looks at the screen on every frame and only touches the UI when the target changed.
//           MARKS_REFRESH_SECONDS > 0 slows that look down.
//           Everything is in Config/XComUniqueTraits.ini [UniqueTraits.UT_PromotionMarks] and meant to be tuned without recompiling.
//           The same panel draws the SYMBOLS of Predestined (UT_Trait_Predestined) on the class perks of its holder: a purple diamond, two green bands, a red cross, white
//           waves (three bars), a blue square, a yellow circle (two squares, one turned by 45 degrees). Two placements to compare (PREDESTINED_MARK_MODE, the console command UTPredestinedMarks
//           changes it while the game runs): 0 = BEHIND the icon, as large as the icon's square, like the diamond of Someone different; 1 = small, in the top right corner
//           of the icon, above it, with a thin dark border. Each icon gets six boxes (three borders, then three fills), created once and reshaped when its symbol changes. The panel also keeps the holder's
//           symbols / points / stats in step with the perks he owns: no event reports a purchase, so every frame it asks UT_Trait_Predestined whether a sync is due.
//---------------------------------------------------------------------------------------
class UT_PromotionMarks extends UIPanel config(UniqueTraits);

const MAX_ICONS_PER_COLUMN = 8;
const PART_COUNT = 3;           // shapes of a symbol have at most three parts
const BOXES_PER_SLOT = 6;       // PART_COUNT border boxes (drawn first) then PART_COUNT fill boxes

var config bool PROMOTION_MARKS_ENABLED;
var config float MARKS_REFRESH_SECONDS;
var config int MARKS_ICON_SIZE, MARKS_ICON_OFFSET_X, MARKS_ICON_OFFSET_Y, MARKS_DIAMOND_OFFSET_X, MARKS_DIAMOND_OFFSET_Y;
var config string MARKS_DIAMOND_COLOR;

// Predestined's symbols: placement (0 behind the icon, 1 small in its corner), size / offset of the small ones, colors (hex RRGGBB) and the two images.
var config int PREDESTINED_MARK_MODE, MARKS_CORNER_SIZE, MARKS_CORNER_INSET, MARKS_CORNER_OFFSET_X, MARKS_CORNER_OFFSET_Y, PD_BORDER_SIZE;
var config bool PREDESTINED_HIDE_OWNED_MARKS;   // no symbol on a perk the soldier already owns (the green check is drawn by the column itself, below every widget we add)
var config string PD_COLOR_DIAMOND, PD_COLOR_BANDS, PD_COLOR_CROSS, PD_COLOR_WAVES, PD_COLOR_SQUARE, PD_COLOR_CIRCLE, PD_COLOR_BORDER;

var array<UIBGBox> Diamonds;          // MAX_ICONS_PER_COLUMN slots per column of the screen (none = not created), children of the COLUMN
var array<bool> ColumnReady;          // the diamonds of this column exist
var float TickAccumulator;

var array<UIBGBox> SymbolBoxes;              // Predestined: BOXES_PER_SLOT per slot (Slot * BOXES_PER_SLOT + k), the slots of the diamonds
var array<int> SymbolKind;                   // the symbol each slot shows now (0 = none)
var array<float> SymbolCX, SymbolCY;         // the point each slot's symbol is centered on (placement of SymbolModeApplied)
var array<bool> SymbolReady;                 // the widgets of this column exist
var int SymbolModeApplied;                   // the placement the widgets were built for
var int LastHeaderIndex;                     // history index at which the soldier header was last redrawn by us (a stat that arrived with a purchase showed one purchase late)
var int LastSyncIndex;                       // history index of the last sync attempt (no retry until a new state exists)

simulated function UT_PromotionMarks InitMarks()
{
	InitPanel();

	return self;
}

// Every frame by default (MARKS_REFRESH_SECONDS = 0): Refresh only compares what the screen shows with what was marked, and the UI calls it
// makes (Show / Hide) are skipped when nothing changes.
simulated event Tick(float DeltaTime)
{
	TickAccumulator += DeltaTime;
	if (TickAccumulator >= default.MARKS_REFRESH_SECONDS)
	{
		TickAccumulator = 0.0;
		Refresh();
	}
}

// The icon of the column showing the ability at row Row of the soldier's tree for that rank, or INDEX_NONE (no such ability, scrolled out).
simulated function int FindIcon(UIArmory_PromotionHero PromotionScreen, XComGameState_Unit Unit, int ColumnIndex, int Row)
{
	local array<SoldierClassAbilityType> RankAbilities;
	local int IconIndex;

	if (Row < 0 || ColumnIndex >= PromotionScreen.Columns.Length)
		return INDEX_NONE;

	RankAbilities = Unit.GetRankAbilities(ColumnIndex);
	if (Row >= RankAbilities.Length)
		return INDEX_NONE;

	IconIndex = PromotionScreen.Columns[ColumnIndex].AbilityNames.Find(RankAbilities[Row].AbilityName);
	if (IconIndex >= PromotionScreen.Columns[ColumnIndex].AbilityIcons.Length)
		return INDEX_NONE;

	return IconIndex;
}

simulated function Refresh()
{
	local UIArmory_PromotionHero PromotionScreen;
	local XComGameState_Unit Unit;
	local int ColumnIndex;
	local bool bMark, bPredestined;

	PromotionScreen = UIArmory_PromotionHero(Screen);
	if (PromotionScreen == none)
		return;

	Unit = PromotionScreen.GetUnit();
	if (Unit == none)
		return;

	// Predestined: first the soldier is brought in step with the perks he owns (a purchase leaves no event); the screen is repopulated then, so the marks wait for the next frame.
	bPredestined = class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Predestined') && class'UT_Trait_Predestined'.static.IsReady(Unit);
	if (bPredestined && SyncPredestined(PromotionScreen, Unit))
		return;

	// Predestined: once per new history state, after the purchase and every handler of it (the stats of the chosen perk are in the unit from the purchase on), the header is redrawn and
	// the screen signals that it received the focus. Signalling the focus is how the base game tells the mods that listen to screens that the soldier shown changed (UIArmory.uc, SignalOnReceiveFocus).
	if (bPredestined && `XCOMHISTORY.GetCurrentHistoryIndex() != LastHeaderIndex)
	{
		LastHeaderIndex = `XCOMHISTORY.GetCurrentHistoryIndex();
		PromotionScreen.Header.PopulateData();
		PromotionScreen.SignalOnReceiveFocus();
	}

	// The placement changed (console command): the widgets are built again.
	if (SymbolModeApplied != default.PREDESTINED_MARK_MODE)
		ResetSymbols();

	// The squaddie column (0) carries no evolution.
	bMark = class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_SomeoneDifferent') && class'UT_Trait_SomeoneDifferent'.static.IsMutated(Unit);
	for (ColumnIndex = 1; ColumnIndex < PromotionScreen.Columns.Length; ++ColumnIndex)
	{
		MarkColumn(PromotionScreen, Unit, ColumnIndex, bMark);
		MarkSymbols(PromotionScreen, Unit, ColumnIndex, bPredestined);
	}
}

// Predestined: syncs the holder when it is due (a perk chosen, a respec...), once per history state. True if a state was submitted (the screen is repopulated).
simulated function bool SyncPredestined(UIArmory_PromotionHero PromotionScreen, XComGameState_Unit Unit)
{
	local int HistoryIndex;

	HistoryIndex = `XCOMHISTORY.GetCurrentHistoryIndex();
	if (HistoryIndex == LastSyncIndex || !class'UT_Trait_Predestined'.static.NeedsSync(Unit))
		return false;

	LastSyncIndex = HistoryIndex;
	if (!class'UT_Trait_Predestined'.static.SyncUnit(Unit.GetReference()))
		return false;

	LastSyncIndex = `XCOMHISTORY.GetCurrentHistoryIndex();
	PromotionScreen.Header.PopulateData();
	PromotionScreen.PopulateData();

	return true;
}

// The square (side MARKS_ICON_SIZE) turns around its top-left corner; to have its center on the icon's, it is placed at the icon's center X and at
// (center Y - side * sqrt(2) / 2). Created once the flash side of the column's icons exists (their position is read from flash).
// We create a diamond for each ability, but only is displayed by column. When we scroll, we only show/hide the right diamonds (see MarkColumn)
// Like this, we avoid moving diamond each time.
simulated function EnsureDiamonds(UIArmory_PromotionHeroColumn Column, int ColumnIndex, int ColumnCount)
{
	local UIBGBox Diamond;
	local float CenterX, CenterY, Side;
	local int IconIndex, IconCount;

	if (ColumnReady.Length < ColumnCount)
	{
		ColumnReady.Length = ColumnCount;
		Diamonds.Length = ColumnCount * MAX_ICONS_PER_COLUMN;
	}

	if (ColumnReady[ColumnIndex])
		return;

	IconCount = Min(Column.AbilityIcons.Length, MAX_ICONS_PER_COLUMN);
	for (IconIndex = 0; IconIndex < IconCount; ++IconIndex)
	{
		if (!Column.AbilityIcons[IconIndex].bIsInited)
			return;
	}

	Side = default.MARKS_ICON_SIZE;
	for (IconIndex = 0; IconIndex < IconCount; ++IconIndex)
	{
		CenterX = Column.AbilityIcons[IconIndex].MC.GetNum("_x") + default.MARKS_ICON_OFFSET_X + default.MARKS_DIAMOND_OFFSET_X + Side / 2.0;
		CenterY = Column.AbilityIcons[IconIndex].MC.GetNum("_y") + default.MARKS_ICON_OFFSET_Y + default.MARKS_DIAMOND_OFFSET_Y + Side / 2.0;

		Diamond = Column.Spawn(class'UIBGBox', Column).InitBG(, CenterX, CenterY - Side * 0.70711, Side, Side);
		Diamond.SetOutline(false, default.MARKS_DIAMOND_COLOR);
		Diamond.SetRotationDegrees(45);
		Diamond.Hide();
		Diamonds[ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex] = Diamond;
	}

	// The diamonds are newer than the icons, so they are drawn above them: bring the icons back to the top. The "?" info buttons are siblings of the
	// icons too (Spawn(class'UIButton', Column) in CreateInfoButton) and were above them: they go back to the top after the icons.
	for (IconIndex = 0; IconIndex < Column.AbilityIcons.Length; ++IconIndex)
		Column.AbilityIcons[IconIndex].MoveToHighestDepth();
	for (IconIndex = 0; IconIndex < Column.InfoButtons.Length; ++IconIndex)
		Column.InfoButtons[IconIndex].MoveToHighestDepth();

	ColumnReady[ColumnIndex] = true;
}

// Shows the diamond behind the evolution of the column (bMark) and hides every other one of the column.
simulated function MarkColumn(UIArmory_PromotionHero PromotionScreen, XComGameState_Unit Unit, int ColumnIndex, bool bMark)
{
	local UIArmory_PromotionHeroColumn Column;
	local int TargetIcon, IconIndex;

	Column = PromotionScreen.Columns[ColumnIndex];
	if (bMark)
		EnsureDiamonds(Column, ColumnIndex, PromotionScreen.Columns.Length);

	if (ColumnIndex >= ColumnReady.Length || !ColumnReady[ColumnIndex])
		return;

	// Only a valid evolution (a class row) is marked: the stored row of an older mutation is redrawn when the stats are synced (screen closing).
	TargetIcon = INDEX_NONE;
	if (bMark && class'UT_Trait_SomeoneDifferent'.static.IsEvolutionValid(Unit, ColumnIndex))
		TargetIcon = FindIcon(PromotionScreen, Unit, ColumnIndex, class'UT_Trait_SomeoneDifferent'.static.GetEvolutionRow(Unit, ColumnIndex));

	for (IconIndex = 0; IconIndex < MAX_ICONS_PER_COLUMN && IconIndex < Column.AbilityIcons.Length; ++IconIndex)
	{
		if (Diamonds[ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex] == none)
			continue;

		if (IconIndex == TargetIcon && Column.AbilityIcons[IconIndex].bIsVisible)
			Diamonds[ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex].Show();
		else
			Diamonds[ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex].Hide();
	}
}

// Predestined: the six boxes of each icon of the column (three borders, then three fills: they are created in that order so that no border is drawn over a fill), hidden,
// created once the icons exist (their position is read from flash). Mode 0 (behind) is centered on the icon; the icons and the "?" buttons are then brought back above them.
// Mode 1 (corner) is centered near the TOP RIGHT corner of the icon's square, MARKS_CORNER_INSET pixels towards the center: the boxes are newer than the icon, so they are
// drawn above it; only the "?" buttons are brought back to the top.
simulated function EnsureSymbols(UIArmory_PromotionHeroColumn Column, int ColumnIndex, int ColumnCount)
{
	local float Side, IconX, IconY;
	local int IconIndex, IconCount, Slot, BoxIndex;
	local bool bBehind;

	if (SymbolReady.Length < ColumnCount)
	{
		SymbolReady.Length = ColumnCount;
		SymbolBoxes.Length = ColumnCount * MAX_ICONS_PER_COLUMN * BOXES_PER_SLOT;
		SymbolKind.Length = ColumnCount * MAX_ICONS_PER_COLUMN;
		SymbolCX.Length = ColumnCount * MAX_ICONS_PER_COLUMN;
		SymbolCY.Length = ColumnCount * MAX_ICONS_PER_COLUMN;
	}

	if (SymbolReady[ColumnIndex])
		return;

	IconCount = Min(Column.AbilityIcons.Length, MAX_ICONS_PER_COLUMN);
	for (IconIndex = 0; IconIndex < IconCount; ++IconIndex)
	{
		if (!Column.AbilityIcons[IconIndex].bIsInited)
			return;
	}

	SymbolModeApplied = default.PREDESTINED_MARK_MODE;
	bBehind = SymbolModeApplied == 0;
	Side = default.MARKS_ICON_SIZE;
	for (IconIndex = 0; IconIndex < IconCount; ++IconIndex)
	{
		Slot = ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex;
		IconX = Column.AbilityIcons[IconIndex].MC.GetNum("_x") + default.MARKS_ICON_OFFSET_X;
		IconY = Column.AbilityIcons[IconIndex].MC.GetNum("_y") + default.MARKS_ICON_OFFSET_Y;
		if (bBehind)
		{
			SymbolCX[Slot] = IconX + default.MARKS_DIAMOND_OFFSET_X + Side / 2.0;
			SymbolCY[Slot] = IconY + default.MARKS_DIAMOND_OFFSET_Y + Side / 2.0;
		}
		else
		{
			SymbolCX[Slot] = IconX + Side - default.MARKS_CORNER_INSET + default.MARKS_CORNER_OFFSET_X;
			SymbolCY[Slot] = IconY + default.MARKS_CORNER_INSET + default.MARKS_CORNER_OFFSET_Y;
		}

		for (BoxIndex = 0; BoxIndex < BOXES_PER_SLOT; ++BoxIndex)
		{
			SymbolBoxes[Slot * BOXES_PER_SLOT + BoxIndex] = Column.Spawn(class'UIBGBox', Column).InitBG(, SymbolCX[Slot], SymbolCY[Slot], 1, 1);
			SymbolBoxes[Slot * BOXES_PER_SLOT + BoxIndex].Hide();
		}

		SymbolKind[Slot] = 0;
	}

	// Behind: the icons go back above the boxes. Always: the "?" buttons stay in front of everything we add.
	if (bBehind)
	{
		for (IconIndex = 0; IconIndex < Column.AbilityIcons.Length; ++IconIndex)
			Column.AbilityIcons[IconIndex].MoveToHighestDepth();
	}
	for (IconIndex = 0; IconIndex < Column.InfoButtons.Length; ++IconIndex)
		Column.InfoButtons[IconIndex].MoveToHighestDepth();

	SymbolReady[ColumnIndex] = true;
}

// The placement changed: the widgets are removed and will be built again, with the new geometry, the next time a column needs them.
simulated function ResetSymbols()
{
	local int i;

	for (i = 0; i < SymbolBoxes.Length; ++i)
	{
		if (SymbolBoxes[i] != none)
			SymbolBoxes[i].Remove();
	}

	SymbolBoxes.Length = 0;
	SymbolKind.Length = 0;
	SymbolCX.Length = 0;
	SymbolCY.Length = 0;
	SymbolReady.Length = 0;
	SymbolModeApplied = default.PREDESTINED_MARK_MODE;
}

// Shows on each icon of the column the symbol Predestined drew for its perk (bPredestined), and hides every other one. Only the slots whose symbol changed are touched.
simulated function MarkSymbols(UIArmory_PromotionHero PromotionScreen, XComGameState_Unit Unit, int ColumnIndex, bool bPredestined)
{
	local UIArmory_PromotionHeroColumn Column;
	local array<SoldierClassAbilityType> RankAbilities;
	local array<int> Wanted;
	local int Row, IconIndex, Slot;

	Column = PromotionScreen.Columns[ColumnIndex];
	if (bPredestined)
		EnsureSymbols(Column, ColumnIndex, PromotionScreen.Columns.Length);

	if (ColumnIndex >= SymbolReady.Length || !SymbolReady[ColumnIndex])
		return;

	Wanted.Length = MAX_ICONS_PER_COLUMN;
	if (bPredestined)
	{
		RankAbilities = Unit.GetRankAbilities(ColumnIndex);
		for (Row = 0; Row < RankAbilities.Length; ++Row)
		{
			IconIndex = Column.AbilityNames.Find(RankAbilities[Row].AbilityName);
			if (IconIndex != INDEX_NONE && IconIndex < MAX_ICONS_PER_COLUMN && IconIndex < Column.AbilityIcons.Length && Column.AbilityIcons[IconIndex].bIsVisible)
			{
				if (!default.PREDESTINED_HIDE_OWNED_MARKS || !class'UT_Trait_Predestined'.static.IsOwned(Unit, ColumnIndex, Row))
					Wanted[IconIndex] = class'UT_Trait_Predestined'.static.GetSymbol(Unit, ColumnIndex, Row);
			}
		}
	}

	for (IconIndex = 0; IconIndex < MAX_ICONS_PER_COLUMN && IconIndex < Column.AbilityIcons.Length; ++IconIndex)
	{
		Slot = ColumnIndex * MAX_ICONS_PER_COLUMN + IconIndex;
		if (SymbolBoxes[Slot * BOXES_PER_SLOT] == none || SymbolKind[Slot] == Wanted[IconIndex])
			continue;

		ApplySymbol(Slot, Wanted[IconIndex]);
		SymbolKind[Slot] = Wanted[IconIndex];
	}
}

// Draws Kind (UT_Trait_Predestined SYMBOL_*, 0 = nothing) in the slot. D is the side of the square the symbol fits in: the icon's (mode 0, the shapes stick out of the round
// icon) or the small corner one (mode 1, which also gets a border of PD_BORDER_SIZE pixels).
simulated function ApplySymbol(int Slot, int Kind)
{
	local float CX, CY, D, Wide, Thick, Edge, Border;
	local bool bBehind;
	local int BoxIndex;

	bBehind = default.PREDESTINED_MARK_MODE == 0;
	D = bBehind ? float(default.MARKS_ICON_SIZE) : float(default.MARKS_CORNER_SIZE);
	Border = bBehind ? 0.0 : float(default.PD_BORDER_SIZE);
	CX = SymbolCX[Slot];
	CY = SymbolCY[Slot];

	for (BoxIndex = 0; BoxIndex < BOXES_PER_SLOT; ++BoxIndex)
	{
		SymbolBoxes[Slot * BOXES_PER_SLOT + BoxIndex].SetRotationDegrees(0);
		SymbolBoxes[Slot * BOXES_PER_SLOT + BoxIndex].Hide();
	}

	if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_DIAMOND)
	{
		// A square turned by 45 degrees around its top-left corner (see EnsureDiamonds).
		Edge = bBehind ? D : D * 0.71;
		DrawPart(Slot, 0, default.PD_COLOR_DIAMOND, CX, CY, Edge, Edge, true, Border);
	}
	else if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_SQUARE)
	{
		// Behind the round icon only the four corners of the square show: as large as the icon, they stick out by about 12 pixels like the tips of the diamond.
		Edge = bBehind ? D : D * 0.8;
		DrawPart(Slot, 0, default.PD_COLOR_SQUARE, CX, CY, Edge, Edge, false, Border);
	}
	else if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_BANDS)
	{
		// Two horizontal bands, one above the other.
		Wide = bBehind ? D * 1.25 : D;
		Thick = D * 0.22;
		DrawPart(Slot, 0, default.PD_COLOR_BANDS, CX, CY - D * 0.2, Wide, Thick, false, Border);
		DrawPart(Slot, 1, default.PD_COLOR_BANDS, CX, CY + D * 0.2, Wide, Thick, false, Border);
	}
	else if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_CROSS)
	{
		Wide = bBehind ? D * 1.25 : D;
		Thick = D * 0.3;
		DrawPart(Slot, 0, default.PD_COLOR_CROSS, CX, CY, Wide, Thick, false, Border);
		DrawPart(Slot, 1, default.PD_COLOR_CROSS, CX, CY, Thick, Wide, false, Border);
	}
	else if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_WAVES)
	{
		// Three horizontal bars (boxes only: an image came out as a huge white square): the top and bottom ones stick out to the LEFT only, the middle one to the RIGHT only.
		Wide = bBehind ? D * 1.1 : D * 0.85;
		Thick = D * 0.16;
		Edge = D * 0.2;
		DrawPart(Slot, 0, default.PD_COLOR_WAVES, CX - Edge / 2.0, CY - D * 0.27, Wide + Edge, Thick, false, Border);
		DrawPart(Slot, 1, default.PD_COLOR_WAVES, CX + Edge / 2.0, CY, Wide + Edge, Thick, false, Border);
		DrawPart(Slot, 2, default.PD_COLOR_WAVES, CX - Edge / 2.0, CY + D * 0.27, Wide + Edge, Thick, false, Border);
	}
	else if (Kind == class'UT_Trait_Predestined'.const.SYMBOL_CIRCLE)
	{
		// A square whose corners stick out of the icon and the same square turned by 45 degrees around its top-left corner, like the purple diamond (an eight-pointed star).
		Edge = bBehind ? D : D * 0.75;
		DrawPart(Slot, 0, default.PD_COLOR_CIRCLE, CX, CY, Edge, Edge, false, Border);
		DrawPart(Slot, 1, default.PD_COLOR_CIRCLE, CX, CY, Edge, Edge, true, Border);
	}
}

// One part of a symbol: a W x H rectangle centered on (CX, CY), or a square turned by 45 degrees (bTurned, side W) with the same center. With a Border > 0 a dark box larger by Border
// on every side is placed in the border layer (Part) under the fill (PART_COUNT + Part).
simulated function DrawPart(int Slot, int Part, string FillColor, float CX, float CY, float W, float H, bool bTurned, float Border)
{
	if (Border > 0.0)
		PlaceBox(Slot * BOXES_PER_SLOT + Part, default.PD_COLOR_BORDER, CX, CY, W + 2.0 * Border, H + 2.0 * Border, bTurned);

	PlaceBox(Slot * BOXES_PER_SLOT + PART_COUNT + Part, FillColor, CX, CY, W, H, bTurned);
}

simulated function PlaceBox(int BoxIndex, string HexColor, float CX, float CY, float W, float H, bool bTurned)
{
	local UIBGBox SymbolBox;

	SymbolBox = SymbolBoxes[BoxIndex];
	SymbolBox.SetOutline(false, HexColor);
	SymbolBox.SetSize(W, H);
	if (bTurned)
	{
		// A box turns around its top-left corner: the turned square is placed so that its center is (CX, CY).
		SymbolBox.SetPosition(CX, CY - W * 0.70711);
		SymbolBox.SetRotationDegrees(45);
	}
	else
	{
		SymbolBox.SetPosition(CX - W / 2.0, CY - H / 2.0);
	}
	SymbolBox.Show();
}
