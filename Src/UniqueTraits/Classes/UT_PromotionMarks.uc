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
//---------------------------------------------------------------------------------------
class UT_PromotionMarks extends UIPanel config(UniqueTraits);

const MAX_ICONS_PER_COLUMN = 8;

var config bool PROMOTION_MARKS_ENABLED;
var config float MARKS_REFRESH_SECONDS;
var config int MARKS_ICON_SIZE, MARKS_ICON_OFFSET_X, MARKS_ICON_OFFSET_Y, MARKS_DIAMOND_OFFSET_X, MARKS_DIAMOND_OFFSET_Y;
var config string MARKS_DIAMOND_COLOR;

var array<UIBGBox> Diamonds;          // MAX_ICONS_PER_COLUMN slots per column of the screen (none = not created), children of the COLUMN
var array<bool> ColumnReady;          // the diamonds of this column exist
var float TickAccumulator;

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
	local bool bMark;

	PromotionScreen = UIArmory_PromotionHero(Screen);
	if (PromotionScreen == none)
		return;

	Unit = PromotionScreen.GetUnit();
	if (Unit == none)
		return;

	// The squaddie column (0) carries no evolution.
	bMark = class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_SomeoneDifferent') && class'UT_Trait_SomeoneDifferent'.static.IsMutated(Unit);
	for (ColumnIndex = 1; ColumnIndex < PromotionScreen.Columns.Length; ++ColumnIndex)
		MarkColumn(PromotionScreen, Unit, ColumnIndex, bMark);
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
