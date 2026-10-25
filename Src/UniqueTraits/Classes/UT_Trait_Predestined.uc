//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Predestined.uc
//  PURPOSE: Predestined (user design 2026-10-24): the soldier no longer earns ability points when he ranks up. Every class perk of his tree (the squaddie column excepted, and
//           only the CLASS rows: never the pistol / XCOM rows) carries a hidden SYMBOL, drawn once the class is known, that decides what choosing the perk gives him:
//             - purple DIAMOND (exactly one per column): ability points, as many as the level that opened the column gave (AP of one promotion) + PREDESTINED_AP_BONUS;
//             - two green BANDS: +PREDESTINED_MOBILITY_BONUS Mobility;     - red CROSS: +PREDESTINED_HP_BONUS HP;
//             - white WAVES: +PREDESTINED_DODGE_BONUS Dodge and half of the diamond's points (rounded down);
//             - blue SQUARE: +PREDESTINED_HACKING_BONUS Hacking (only when the class can equip a gremlin or a BIT);   - yellow CIRCLE: +PREDESTINED_AIM_BONUS Aim.
//           The symbols of a column are all different. They are marked on the promotion screen (UT_PromotionMarks) and explained in the popup of the "?" button of the perk
//           (the tag <Ability:UT_PredestinedNote/>, appended to the LocPromotionPopupText of every class ability by OnPostTemplatesCreated, expands to nothing for anybody else).
//           How it is kept right (everything is a diff against what is already applied, so every sync is idempotent, as for Someone different):
//             - SYMBOLS: UnitValues UT_PD_Col_<column> (the symbol of each row, 3 bits per row), UT_PD_Class (a key of the class: another class draws again).
//             - STATS: the permanent stat changes of the perks owned (m_SoldierProgressionAbilties), through the ledger of UT_TraitBase (ShiftStatTo): a respec takes them back.
//             - ABILITY POINTS: the points the soldier may have EARNED in all (AbilityPoints + SpentAbilityPoints) are exactly the points granted by the diamonds / waves he owns
//               (UnitValues UT_PD_APA_<column> and UT_PD_APB_<column>: the amount granted, 0 = not granted). A level-up that gave points, the trait given to a soldier who already
//               has some, a respec that refunded the spent points... all bring the total back to that figure. When the points to take away exceed the unspent ones, the soldier
//               has spent points he no longer has: the perks bought with them (everything but the class perks) are removed as if he had never bought them.
//             - THE GRANT to a soldier already promoted: all his perks (class ones included, except the squaddie ones the game gives) are removed and his points set to 0; he
//               chooses his class perks again for free, each one bringing its bonus. A faction hero cannot get the trait (IsEligibleForUnit): he pays points for his class perks.
//           Sync points: the grant, a rank-up, a respec, the promotion screen (every frame while it is open, no event reports a purchase: UT_PromotionMarks) and the mission start.
//---------------------------------------------------------------------------------------
class UT_Trait_Predestined extends UT_TraitBase config(UniqueTraits);

const SYMBOL_DIAMOND = 1;
const SYMBOL_BANDS = 2;
const SYMBOL_CROSS = 3;
const SYMBOL_WAVES = 4;
const SYMBOL_SQUARE = 5;
const SYMBOL_CIRCLE = 6;

const MAX_COLUMNS = 16;
const NOTE_TAG = "<Ability:UT_PredestinedNote/>";

var config int PREDESTINED_AP_BONUS, PREDESTINED_MOBILITY_BONUS, PREDESTINED_HP_BONUS, PREDESTINED_DODGE_BONUS, PREDESTINED_HACKING_BONUS, PREDESTINED_AIM_BONUS;
// What each perk of the same symbol gives MORE than the one chosen before it (the Nth perk of a symbol gives BONUS + STEP x (N - 1)).
// From the (LIMIT + 1)th perk of the same symbol on, a perk gives no stat bonus: it gives PCT % of the purple symbol's points of its column instead (rounded down).
var config int PREDESTINED_ESCALATION_LIMIT, PREDESTINED_OVERFLOW_AP_PCT;
// The red symbol also gives ablative HP for the mission: the Nth red perk gives BONUS + STEP x (N - 1) of them (0 and 1: none, then 1, then 2).
var config int PREDESTINED_HP_ABLATIVE_BONUS, PREDESTINED_HP_ABLATIVE_STEP;
var config int PREDESTINED_MOBILITY_STEP, PREDESTINED_HP_STEP, PREDESTINED_DODGE_STEP, PREDESTINED_HACKING_STEP, PREDESTINED_AIM_STEP;

// The explanation added to the popup of a perk ([UT_Trait_Predestined] of UniqueTraits.int/.fra): %VALUE is the stat bonus, %AP the ability points.
var localized string PREDESTINED_NOTE_DIAMOND, PREDESTINED_NOTE_BANDS, PREDESTINED_NOTE_CROSS, PREDESTINED_NOTE_WAVES, PREDESTINED_NOTE_SQUARE, PREDESTINED_NOTE_CIRCLE, PREDESTINED_NOTE_OVERFLOW, PREDESTINED_NOTE_TAIL;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;
	local X2AbilityTemplate Template;
	local X2Effect_UT_PredestinedAblative AblativeEffect;

	Template = PurePassive('UT_Predestined', "img:///UniqueTraits_Icons.UT_Predestined", true);

	// The ablative hit points of the red symbol (a mission effect: the amount is computed when it is applied).
	AblativeEffect = new class'X2Effect_UT_PredestinedAblative';
	AblativeEffect.EffectName = 'UT_Predestined_Ablative';
	AblativeEffect.BuildPersistentEffect(1, true, false);
	AblativeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(AblativeEffect);

	Templates.AddItem(Template);

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateStrategyListeners / CreateTacticalListeners call these for every trait of the pool that is not disabled).
static function OnCreateStrategyListeners(CHEventListenerTemplate Template)
{
	// A respec made at the Training Center: the perks go, so do their stats and their points.
	Template.AddCHEvent('CompleteRespecSoldier', OnStatsMayHaveChanged_Predestined, ELD_OnStateSubmitted, 40);
}

static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	// The mission start guarantees the stats in combat.
	Template.AddCHEvent('OnTacticalBeginPlay', OnTacticalBeginPlay_Predestined, ELD_Immediate, 50);
}

//---------------------------------------------------------------------------------------
// The symbols
//---------------------------------------------------------------------------------------

// Number of promotion columns that can carry symbols: all but the squaddie one (column 0), as for Someone different.
static final function int GetColumnCount(XComGameState_Unit Unit)
{
	return Clamp(Unit.AbilityTree.Length - 1, 0, MAX_COLUMNS);
}

// A soldier whose class is known (his tree exists) and who has been promoted to it.
static final function bool IsReady(XComGameState_Unit Unit)
{
	return Unit != none && Unit.IsSoldier() && Unit.GetRank() >= 1 && Unit.GetSoldierClassTemplate() != none && GetColumnCount(Unit) > 0;
}

// A number that changes with the class: another class draws the symbols again.
static final function int GetClassKey(XComGameState_Unit Unit)
{
	local string ClassName;
	local int i, Key;

	ClassName = string(Unit.GetSoldierClassTemplateName());
	for (i = 0; i < Len(ClassName); ++i)
		Key = (Key * 31 + Asc(Mid(ClassName, i, 1))) % 1000003;

	return Key + 1;
}

static final function name ColumnValueName(int Column)
{
	return name("UT_PD_Col_" $ Column);
}

static final function name DiamondApName(int Column)
{
	return name("UT_PD_APA_" $ Column);
}

static final function name WavesApName(int Column)
{
	return name("UT_PD_APB_" $ Column);
}

// The points an OVERFLOW perk (see IsOverflow) of the column granted, per row.
static final function name OverflowApName(int Column, int Row)
{
	return name("UT_PD_APX_" $ Column $ "_" $ Row);
}

// The symbol (SYMBOL_*, 0 = none) of the perk at (Column, Row).
static final function int GetSymbol(XComGameState_Unit Unit, int Column, int Row)
{
	local int Code, i;

	Code = int(GetUnitFloat(Unit, ColumnValueName(Column)));
	for (i = 0; i < Row; ++i)
		Code /= 8;

	return Code % 8;
}

// The row of the column that carries Symbol, INDEX_NONE if none does.
static final function int FindSymbolRow(XComGameState_Unit Unit, int Column, int Symbol)
{
	local array<int> Rows;
	local int i;

	Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
	for (i = 0; i < Rows.Length; ++i)
	{
		if (GetSymbol(Unit, Column, Rows[i]) == Symbol)
			return Rows[i];
	}

	return INDEX_NONE;
}

// True when the class can equip a gremlin or a BIT (the blue square gives Hacking, which only those items use).
static final function bool CanUseHackingItem(XComGameState_Unit Unit)
{
	local X2SoldierClassTemplate ClassTemplate;
	local int i;

	ClassTemplate = Unit.GetSoldierClassTemplate();
	if (ClassTemplate == none)
		return false;

	for (i = 0; i < ClassTemplate.AllowedWeapons.Length; ++i)
	{
		if (ClassTemplate.AllowedWeapons[i].WeaponType == 'gremlin' || ClassTemplate.AllowedWeapons[i].WeaponType == 'sparkbit')
			return true;
	}

	return false;
}

// The column holds a valid draw: it has no class rows at all (nothing to draw), or one of its class rows carries the diamond.
static final function bool IsColumnValid(XComGameState_Unit Unit, int Column)
{
	local array<int> Rows;

	Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
	if (Rows.Length == 0)
		return true;

	return FindSymbolRow(Unit, Column, SYMBOL_DIAMOND) != INDEX_NONE;
}

// Draws the symbols of Column among its class rows: the diamond on a random row, then a different symbol on each other row. The unit must be modifiable.
static final function DrawColumn(XComGameState_Unit MutableUnit, int Column)
{
	local array<int> Rows, Pool;
	local int DiamondRow, i, Pick, Symbol, Weight;
	local float Code;

	MutableUnit.ClearUnitValue(ColumnValueName(Column));
	Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(MutableUnit, Column);
	if (Rows.Length == 0)
		return;

	Pool.AddItem(SYMBOL_BANDS);
	Pool.AddItem(SYMBOL_CROSS);
	Pool.AddItem(SYMBOL_WAVES);
	Pool.AddItem(SYMBOL_CIRCLE);
	if (CanUseHackingItem(MutableUnit))
		Pool.AddItem(SYMBOL_SQUARE);

	DiamondRow = `SYNC_RAND_STATIC(Rows.Length);
	for (i = 0; i < Rows.Length; ++i)
	{
		Symbol = 0;
		if (i == DiamondRow)
		{
			Symbol = SYMBOL_DIAMOND;
		}
		else if (Pool.Length > 0)
		{
			Pick = `SYNC_RAND_STATIC(Pool.Length);
			Symbol = Pool[Pick];
			Pool.Remove(Pick, 1);
		}

		Weight = 1;
		for (Pick = 0; Pick < Rows[i]; ++Pick)
			Weight *= 8;
		Code += float(Symbol * Weight);
	}

	MutableUnit.SetUnitFloatValue(ColumnValueName(Column), Code, eCleanup_Never);
}

// Forgets every symbol and every point granted (the class changed, or the trait goes away).
static final function ClearMarks(XComGameState_Unit MutableUnit)
{
	local int Column, Row;

	MutableUnit.ClearUnitValue('UT_PD_Class');
	for (Column = 1; Column <= MAX_COLUMNS; ++Column)
	{
		MutableUnit.ClearUnitValue(ColumnValueName(Column));
		MutableUnit.ClearUnitValue(DiamondApName(Column));
		MutableUnit.ClearUnitValue(WavesApName(Column));
		for (Row = 0; Row < 12; ++Row)
			MutableUnit.ClearUnitValue(OverflowApName(Column, Row));
	}
}

// True when the soldier owns the perk at (Column, Row) (he chose it).
static final function bool IsOwned(XComGameState_Unit Unit, int Column, int Row)
{
	local int i;

	if (Row < 0)
		return false;

	for (i = 0; i < Unit.m_SoldierProgressionAbilties.Length; ++i)
	{
		if (Unit.m_SoldierProgressionAbilties[i].iRank == Column && Unit.m_SoldierProgressionAbilties[i].iBranch == Row)
			return true;
	}

	return false;
}

//---------------------------------------------------------------------------------------
// What the perks owned give
//---------------------------------------------------------------------------------------

// The ability points one promotion gives the soldier (what the game gave him when the column opened): the same figures as XComGameState_Unit.RankUpSoldier.
static final function int GetLevelAP(XComGameState_Unit Unit, int Column)
{
	if (Unit.IsResistanceHero())
		return Unit.GetResistanceHeroAPAmount(Column + 1, Unit.ComInt);

	return Unit.GetBaseSoldierAPAmount(Unit.ComInt);
}

static final function int GetDiamondAP(XComGameState_Unit Unit, int Column)
{
	return GetLevelAP(Unit, Column) + default.PREDESTINED_AP_BONUS;
}

static final function int GetWavesAP(XComGameState_Unit Unit, int Column)
{
	return GetDiamondAP(Unit, Column) / 2;
}

// The symbol whose perks give Stat (0 = none of them does).
static final function int SymbolOfStat(ECharStatType Stat)
{
	switch (Stat)
	{
		case eStat_Mobility: return SYMBOL_BANDS;
		case eStat_HP: return SYMBOL_CROSS;
		case eStat_Dodge: return SYMBOL_WAVES;
		case eStat_Hacking: return SYMBOL_SQUARE;
		case eStat_Offense: return SYMBOL_CIRCLE;
	}

	return 0;
}

// What a perk of Symbol gives when Previous perks of that symbol were chosen before it: the bonus plus the step for each of them.
static final function int GetSymbolBonus(int Symbol, int Previous)
{
	switch (Symbol)
	{
		case SYMBOL_BANDS: return default.PREDESTINED_MOBILITY_BONUS + default.PREDESTINED_MOBILITY_STEP * Previous;
		case SYMBOL_CROSS: return default.PREDESTINED_HP_BONUS + default.PREDESTINED_HP_STEP * Previous;
		case SYMBOL_WAVES: return default.PREDESTINED_DODGE_BONUS + default.PREDESTINED_DODGE_STEP * Previous;
		case SYMBOL_SQUARE: return default.PREDESTINED_HACKING_BONUS + default.PREDESTINED_HACKING_STEP * Previous;
		case SYMBOL_CIRCLE: return default.PREDESTINED_AIM_BONUS + default.PREDESTINED_AIM_STEP * Previous;
	}

	return 0;
}

// How many perks of Symbol the soldier has chosen, the perk at (SkipColumn, SkipRow) not counted.
static final function int CountOwnedSymbol(XComGameState_Unit Unit, int Symbol, optional int SkipColumn = -1, optional int SkipRow = -1)
{
	local int Column, Row, Count;
	local array<int> Rows;

	for (Column = 1; Column <= GetColumnCount(Unit); ++Column)
	{
		Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
		for (Row = 0; Row < Rows.Length; ++Row)
		{
			if (Column == SkipColumn && Rows[Row] == SkipRow)
				continue;

			if (GetSymbol(Unit, Column, Rows[Row]) == Symbol && IsOwned(Unit, Column, Rows[Row]))
				++Count;
		}
	}

	return Count;
}

// How many perks of Symbol the soldier chose BEFORE the perk at (Column, Row): m_SoldierProgressionAbilties is filled in the order of the purchases (AddItem), so for an owned
// perk it is the number of perks of that symbol that come earlier in the list; for a perk not owned yet, all the ones he owns.
static final function int CountPreviousSymbol(XComGameState_Unit Unit, int Symbol, int Column, int Row)
{
	local int i, Count;

	if (!IsOwned(Unit, Column, Row))
		return CountOwnedSymbol(Unit, Symbol);

	for (i = 0; i < Unit.m_SoldierProgressionAbilties.Length; ++i)
	{
		if (Unit.m_SoldierProgressionAbilties[i].iRank == Column && Unit.m_SoldierProgressionAbilties[i].iBranch == Row)
			break;

		if (Unit.m_SoldierProgressionAbilties[i].iRank >= 1 && Unit.m_SoldierProgressionAbilties[i].iRank <= GetColumnCount(Unit)
			&& GetSymbol(Unit, Unit.m_SoldierProgressionAbilties[i].iRank, Unit.m_SoldierProgressionAbilties[i].iBranch) == Symbol)
			++Count;
	}

	return Count;
}

// The ablative hit points (eStat_ShieldHP) the red perks owned give in a mission: the Nth of them gives ablative bonus + step x (N - 1), only the first PREDESTINED_ESCALATION_LIMIT
// count (the following ones give points). The total only depends on the count, like the other stats.
static final function int GetAblativeAmount(XComGameState_Unit Unit)
{
	local int Count;

	Count = Min(CountOwnedSymbol(Unit, SYMBOL_CROSS), default.PREDESTINED_ESCALATION_LIMIT);

	return Count * default.PREDESTINED_HP_ABLATIVE_BONUS + default.PREDESTINED_HP_ABLATIVE_STEP * Count * (Count - 1) / 2;
}

// The stat shift the perks owned call for. The Nth perk of a symbol gives its bonus + step x (N - 1), so the total only depends on HOW MANY of that symbol are owned (not on the
// order they were chosen in): N x bonus + step x N x (N - 1) / 2. That keeps every sync idempotent and a respec exact.
static final function float GetTargetShift(XComGameState_Unit Unit, ECharStatType Stat)
{
	local int Symbol, Count;

	Symbol = SymbolOfStat(Stat);
	if (Symbol == 0)
		return 0.0;

	// Only the first PREDESTINED_ESCALATION_LIMIT perks of a symbol give a stat (the others give points, IsOverflow): the total still only depends on the count.
	Count = Min(CountOwnedSymbol(Unit, Symbol), default.PREDESTINED_ESCALATION_LIMIT);

	return float(Count * GetSymbolBonus(Symbol, 0) + (GetSymbolBonus(Symbol, 1) - GetSymbolBonus(Symbol, 0)) * Count * (Count - 1) / 2);
}

static final function array<ECharStatType> GetAffectedStats()
{
	local array<ECharStatType> Stats;

	Stats.AddItem(eStat_Mobility);
	Stats.AddItem(eStat_HP);
	Stats.AddItem(eStat_Dodge);
	Stats.AddItem(eStat_Hacking);
	Stats.AddItem(eStat_Offense);

	return Stats;
}

// True when the perk at (Column, Row) gives points instead of a stat: it is the (LIMIT + 1)th or later perk of its symbol (the purple diamond never is).
static final function bool IsOverflow(XComGameState_Unit Unit, int Symbol, int Column, int Row)
{
	return Symbol != 0 && Symbol != SYMBOL_DIAMOND && CountPreviousSymbol(Unit, Symbol, Column, Row) >= default.PREDESTINED_ESCALATION_LIMIT;
}

// What an overflow perk of the column grants: PCT % of the diamond's points, rounded down.
static final function int GetOverflowAP(XComGameState_Unit Unit, int Column)
{
	return GetDiamondAP(Unit, Column) * default.PREDESTINED_OVERFLOW_AP_PCT / 100;
}

// The points the diamonds, waves and overflow perks owned have granted so far (the stored amounts) - the figure the soldier's earned points must equal.
static final function int GetGrantedAP(XComGameState_Unit Unit)
{
	local int Column, Row, Total;
	local array<int> Rows;

	for (Column = 1; Column <= GetColumnCount(Unit); ++Column)
	{
		Total += int(GetUnitFloat(Unit, DiamondApName(Column))) + int(GetUnitFloat(Unit, WavesApName(Column)));

		Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
		for (Row = 0; Row < Rows.Length; ++Row)
			Total += int(GetUnitFloat(Unit, OverflowApName(Column, Rows[Row])));
	}

	return Total;
}

// True when a stored grant of the perk at (Column, Row) does not match what the soldier owns: the diamond / waves / overflow points of a perk chosen and not granted yet, or granted
// and no longer owned (or no longer an overflow perk, or the other way round).
static final function bool RowGrantMismatch(XComGameState_Unit Unit, int Column, int Row)
{
	local int Symbol;
	local bool bOwned, bOverflow;

	Symbol = GetSymbol(Unit, Column, Row);
	if (Symbol == 0)
		return false;

	bOwned = IsOwned(Unit, Column, Row);
	bOverflow = bOwned && IsOverflow(Unit, Symbol, Column, Row);

	if (Symbol == SYMBOL_DIAMOND)
		return bOwned != (GetUnitFloat(Unit, DiamondApName(Column)) != 0.0);

	if (Symbol == SYMBOL_WAVES && (bOwned && !bOverflow) != (GetUnitFloat(Unit, WavesApName(Column)) != 0.0))
		return true;

	return bOverflow != (GetUnitFloat(Unit, OverflowApName(Column, Row)) != 0.0);
}

static final function bool AnyGrantMismatch(XComGameState_Unit Unit)
{
	local int Column, Row;
	local array<int> Rows;

	for (Column = 1; Column <= GetColumnCount(Unit); ++Column)
	{
		Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
		for (Row = 0; Row < Rows.Length; ++Row)
		{
			if (RowGrantMismatch(Unit, Column, Rows[Row]))
				return true;
		}
	}

	return false;
}

//---------------------------------------------------------------------------------------
// Sync
//---------------------------------------------------------------------------------------

// True when SyncState would change the unit (the promotion screen asks every frame: it must stay cheap and agree with SyncState).
static final function bool NeedsSync(XComGameState_Unit Unit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;
	local int Column;

	if (!IsReady(Unit))
		return false;

	if (int(GetUnitFloat(Unit, 'UT_PD_Class')) != GetClassKey(Unit) || WasRespecSinceLastShift(Unit))
		return true;

	for (Column = 1; Column <= GetColumnCount(Unit); ++Column)
	{
		if (!IsColumnValid(Unit, Column))
			return true;
	}

	if (AnyGrantMismatch(Unit) || Unit.AbilityPoints + Unit.SpentAbilityPoints != GetGrantedAP(Unit))
		return true;

	Stats = GetAffectedStats();
	foreach Stats(Stat)
	{
		if (Abs(GetTargetShift(Unit, Stat) - GetStatLedger(Unit, Stat)) >= 0.0005)
			return true;
	}

	return false;
}

// Brings symbols, points and stats to what the soldier's class and perks call for. The unit must be modifiable (a pending state object). True if it changed.
static final function bool SyncState(XComGameState_Unit MutableUnit)
{
	local int Column;
	local bool bChanged;

	if (!IsReady(MutableUnit))
		return false;

	// A respec since the last shift: the ledger is forgotten.
	ForgetIfRespec(MutableUnit);

	// Another class: the symbols (and what they granted) are drawn again.
	if (int(GetUnitFloat(MutableUnit, 'UT_PD_Class')) != GetClassKey(MutableUnit))
	{
		ClearMarks(MutableUnit);
		MutableUnit.SetUnitFloatValue('UT_PD_Class', GetClassKey(MutableUnit), eCleanup_Never);
		bChanged = true;
	}

	for (Column = 1; Column <= GetColumnCount(MutableUnit); ++Column)
	{
		if (!IsColumnValid(MutableUnit, Column))
		{
			DrawColumn(MutableUnit, Column);
			bChanged = true;
		}
	}

	if (SyncAbilityPoints(MutableUnit))
		bChanged = true;

	if (SyncStats(MutableUnit))
		bChanged = true;

	if (bChanged)
		`log("UniqueTraits : Predestined --" @ MutableUnit.GetFullName() @ "rank" @ MutableUnit.GetRank() @ ": AP" @ MutableUnit.AbilityPoints @ "(spent" @ MutableUnit.SpentAbilityPoints $ ", granted" @ GetGrantedAP(MutableUnit) $ "), mobility"
			@ GetStatLedger(MutableUnit, eStat_Mobility) $ ", HP" @ GetStatLedger(MutableUnit, eStat_HP) $ ", dodge" @ GetStatLedger(MutableUnit, eStat_Dodge) $ ", hacking" @ GetStatLedger(MutableUnit, eStat_Hacking)
			$ ", aim" @ GetStatLedger(MutableUnit, eStat_Offense),, 'UniqueTraits');

	return bChanged;
}

static final function bool SyncStats(XComGameState_Unit MutableUnit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;
	local bool bChanged;

	Stats = GetAffectedStats();
	foreach Stats(Stat)
	{
		if (!ShiftStatTo(MutableUnit, Stat, GetTargetShift(MutableUnit, Stat)))
			continue;

		if (Stat == eStat_HP && MutableUnit.GetCurrentStat(eStat_HP) < 1)
			MutableUnit.SetCurrentStat(eStat_HP, 1);
		bChanged = true;
	}

	return bChanged;
}

// Records (Wanted) or forgets (not Wanted) a grant of points under ValueName. A figure of 0 would look like "not granted": 1 point at least is recorded. True if it changed.
static final function bool SetGrant(XComGameState_Unit MutableUnit, name ValueName, bool bWanted, int Amount)
{
	local int Stored;

	Stored = int(GetUnitFloat(MutableUnit, ValueName));
	if (bWanted && Stored == 0)
	{
		MutableUnit.SetUnitFloatValue(ValueName, Max(1, Amount), eCleanup_Never);
		return true;
	}

	if (!bWanted && Stored != 0)
	{
		MutableUnit.ClearUnitValue(ValueName);
		return true;
	}

	return false;
}

// Grants the points of the diamonds / waves chosen, takes back those of the perks no longer owned, and brings the points the soldier has earned in all (unspent + spent) to
// the figure granted. A level-up that gave points, a refund of spent points after a respec, the trait given to a soldier who already has points: the excess goes.
static final function bool SyncAbilityPoints(XComGameState_Unit MutableUnit)
{
	local int Column, Row, Symbol, Target, Total, Excess;
	local array<int> Rows;
	local bool bChanged, bOwned, bOverflow;

	for (Column = 1; Column <= GetColumnCount(MutableUnit); ++Column)
	{
		Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(MutableUnit, Column);
		for (Row = 0; Row < Rows.Length; ++Row)
		{
			Symbol = GetSymbol(MutableUnit, Column, Rows[Row]);
			if (Symbol == 0)
				continue;

			bOwned = IsOwned(MutableUnit, Column, Rows[Row]);
			bOverflow = bOwned && IsOverflow(MutableUnit, Symbol, Column, Rows[Row]);

			if (Symbol == SYMBOL_DIAMOND)
			{
				if (SetGrant(MutableUnit, DiamondApName(Column), bOwned, GetDiamondAP(MutableUnit, Column)))
					bChanged = true;
			}
			else
			{
				if (Symbol == SYMBOL_WAVES && SetGrant(MutableUnit, WavesApName(Column), bOwned && !bOverflow, GetWavesAP(MutableUnit, Column)))
					bChanged = true;

				if (SetGrant(MutableUnit, OverflowApName(Column, Rows[Row]), bOverflow, GetOverflowAP(MutableUnit, Column)))
					bChanged = true;
			}
		}
	}

	Target = GetGrantedAP(MutableUnit);
	Total = MutableUnit.AbilityPoints + MutableUnit.SpentAbilityPoints;
	if (Total == Target)
		return bChanged;

	if (Total < Target)
	{
		MutableUnit.AbilityPoints += Target - Total;
	}
	else
	{
		Excess = Total - Target;
		if (Excess <= MutableUnit.AbilityPoints)
		{
			MutableUnit.AbilityPoints -= Excess;
		}
		else
		{
			// The points to take away are partly spent: the perks bought with them go, as if he had never bought them, and what is left is exactly the figure granted.
			RemovePurchasedPerks(MutableUnit);
			MutableUnit.SpentAbilityPoints = 0;
			MutableUnit.AbilityPoints = Target;
		}
	}

	`XEVENTMGR.TriggerEvent('AbilityPointsChange', MutableUnit, , MutableUnit.GetParentGameState());

	return true;
}

// Removes every perk the soldier chose (rank 1 and above), class perks included: the squaddie perks (rank 0) are given by the game, not bought, and stay. Used when the trait is given.
static final function RemoveAllPerks(XComGameState_Unit MutableUnit)
{
	local array<SCATProgression> Kept;
	local SCATProgression Perk;
	local int i;

	for (i = 0; i < MutableUnit.m_SoldierProgressionAbilties.Length; ++i)
	{
		Perk = MutableUnit.m_SoldierProgressionAbilties[i];
		if (Perk.iRank == 0)
			Kept.AddItem(Perk);
	}

	if (Kept.Length != MutableUnit.m_SoldierProgressionAbilties.Length)
		MutableUnit.SetSoldierProgression(Kept);
}

// A faction hero pays ability points for his class perks: the trait would take his only way to learn them.
static function bool IsEligibleForUnit(XComGameState_Unit Unit)
{
	return Unit == none || !Unit.IsResistanceHero();
}

// Removes the perks that were bought with ability points: everything of the progression but the CLASS perks (which are free and are not touched: they are not bought again, so
// their purchase function does not run a second time). The progression is written back with SetSoldierProgression (m_SoldierProgressionAbilties is protectedwrite).
static final function RemovePurchasedPerks(XComGameState_Unit MutableUnit)
{
	local array<SCATProgression> Kept;
	local SCATProgression Perk;
	local int i;

	for (i = 0; i < MutableUnit.m_SoldierProgressionAbilties.Length; ++i)
	{
		Perk = MutableUnit.m_SoldierProgressionAbilties[i];
		if (Perk.iBranch < class'UT_Trait_SomeoneDifferent'.static.GetClassRowCount(MutableUnit, Perk.iRank))
			Kept.AddItem(Perk);
	}

	if (Kept.Length != MutableUnit.m_SoldierProgressionAbilties.Length)
		MutableUnit.SetSoldierProgression(Kept);
}

//---------------------------------------------------------------------------------------
// Hooks (UT_TraitBase)
//---------------------------------------------------------------------------------------

static function bool ShiftsStats()
{
	return true;
}

// A real promotion: the points the level gave are taken back, and the first rank-up (the class is chosen) draws the symbols.
static function bool OnRankUp(XComGameState_Unit MutableUnit)
{
	return SyncState(MutableUnit);
}

// The base stats were rebuilt by a respec: the shifts are gone with them (forgotten without touching the stats), the perks too; everything is brought right again.
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	ForgetShifts(MutableUnit);
	SyncState(MutableUnit);
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// Defensive: a unit that had the trait before was cleared by OnClear. A soldier who is already promoted (user decision 2026-10-24, second version): he loses ALL his ability
	// points and ALL his perks, class perks included (the squaddie ones, which the game gives and the player cannot choose, stay); he chooses his class perks again, for free, and
	// each one brings its symbol's bonus.
	ClearMarks(MutableUnit);
	if (IsReady(MutableUnit))
	{
		RemoveAllPerks(MutableUnit);
		MutableUnit.SpentAbilityPoints = 0;
		MutableUnit.AbilityPoints = 0;
	}
	SyncState(MutableUnit);
}

// The trait is already out of AcquiredTraits here. The stat changes are taken back (exactly the ledger); the points granted stay in the soldier's total as ordinary points.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	RevertShifts(MutableUnit);
	ClearMarks(MutableUnit);
}

// 'CompleteRespecSoldier' (EventSource = the unit), ELD_OnStateSubmitted: the change is committed, the sync goes in a transaction of its own.
static function EventListenerReturn OnStatsMayHaveChanged_Predestined(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Unit;

	Unit = XComGameState_Unit(EventData);
	if (Unit == none)
		Unit = XComGameState_Unit(EventSource);
	if (Unit != none)
		SyncUnit(Unit.GetReference());

	return ELR_NoInterrupt;
}

// A transaction of its own, only when something has to change (also called by the promotion screen: UT_PromotionMarks, UIScreenListener_UT_PromotionMarks).
static final function bool SyncUnit(StateObjectReference UnitRef)
{
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState NewGameState;

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Predestined') || !NeedsSync(Unit))
		return false;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Predestined sync");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
	if (SyncState(MutableUnit))
	{
		`GAMERULES.SubmitGameState(NewGameState);
		return true;
	}

	`XCOMHISTORY.CleanupPendingGameState(NewGameState);

	return false;
}

// Mission start: the squad's holders are synced in the mission's own state.
static function EventListenerReturn OnTacticalBeginPlay_Predestined(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;

	if (GameState == none)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Predestined') || !NeedsSync(SquadUnit))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		SyncState(MutableUnit);
	}

	return ELR_NoInterrupt;
}

//---------------------------------------------------------------------------------------
// The note in the popup of the "?" button
//---------------------------------------------------------------------------------------

// Every class ability gets the tag at the end of its promotion popup text (the text of the popup the "?" button of the promotion screen opens); the tag expands to nothing for
// a soldier who is not Predestined, or for an ability that carries no symbol.
static function OnPostTemplatesCreated()
{
	local X2SoldierClassTemplateManager ClassManager;
	local X2AbilityTemplateManager AbilityManager;
	local X2DataTemplate DataTemplate;
	local X2SoldierClassTemplate ClassTemplate;
	local array<SoldierClassAbilitySlot> Slots;
	local SoldierClassAbilitySlot Slot;
	local array<name> Names;
	local array<X2AbilityTemplate> Templates;
	local X2AbilityTemplate AbilityTemplate;
	local name AbilityName;
	local int Rank;

	ClassManager = class'X2SoldierClassTemplateManager'.static.GetSoldierClassTemplateManager();
	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();

	foreach ClassManager.IterateTemplates(DataTemplate, none)
	{
		ClassTemplate = X2SoldierClassTemplate(DataTemplate);
		if (ClassTemplate == none)
			continue;

		for (Rank = 0; Rank < ClassTemplate.GetMaxConfiguredRank(); ++Rank)
		{
			Slots = ClassTemplate.GetAbilitySlots(Rank);
			foreach Slots(Slot)
			{
				if (Slot.AbilityType.AbilityName != '' && Names.Find(Slot.AbilityType.AbilityName) == INDEX_NONE)
					Names.AddItem(Slot.AbilityType.AbilityName);
			}
		}
	}

	foreach Names(AbilityName)
	{
		AbilityManager.FindAbilityTemplateAllDifficulties(AbilityName, Templates);
		foreach Templates(AbilityTemplate)
		{
			if (InStr(AbilityTemplate.LocPromotionPopupText, NOTE_TAG) == INDEX_NONE)
				AbilityTemplate.LocPromotionPopupText $= NOTE_TAG;

			// The description the promotion screen shows for the ability it selects (GetMyLongDescription) gets it too, so the step shows without opening the popup.
			if (AbilityTemplate.LocLongDescription != "" && InStr(AbilityTemplate.LocLongDescription, NOTE_TAG) == INDEX_NONE)
				AbilityTemplate.LocLongDescription $= NOTE_TAG;

			// The purchase function runs inside the state of the purchase, so the points and stats of the chosen perk arrive with it (an ability that has its own is left alone;
			// the promotion screen's per-frame check, UT_PromotionMarks, still catches that one).
			if (AbilityTemplate.SoldierAbilityPurchasedFn == none)
				AbilityTemplate.SoldierAbilityPurchasedFn = OnAbilityPurchased_Predestined;
		}
	}
}

// SoldierAbilityPurchasedFn of the class abilities (X2AbilityTemplate): called by BuySoldierProgressionAbility at the end of the purchase, in the state of the purchase, with the
// unit already holding the new perk. A holder is synced at once, so the promotion screen shows the stat of the chosen perk when it redraws, not one purchase later. Only when the
// soldier owns a perk of rank 1 or above: the squaddie perk is bought again in the middle of a respec (rank-ups of LWOTC's, the Training Center's), when the stats and the
// ledger must not be touched before the respec has been seen (OnStatsReset, SyncUnit).
static function OnAbilityPurchased_Predestined(XComGameState NewGameState, XComGameState_Unit UnitState)
{
	local int i;

	if (UnitState == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(UnitState, 'UT_Predestined') || !IsReady(UnitState))
		return;

	for (i = 0; i < UnitState.m_SoldierProgressionAbilties.Length; ++i)
	{
		if (UnitState.m_SoldierProgressionAbilties[i].iRank >= 1)
		{
			`log("UniqueTraits [DIAG] : purchase hook -- history index" @ `XCOMHISTORY.GetCurrentHistoryIndex() @ "mobility" @ UnitState.GetCurrentStat(eStat_Mobility) @ "dodge" @ UnitState.GetCurrentStat(eStat_Dodge) @ "aim" @ UnitState.GetCurrentStat(eStat_Offense) @ "HP" @ UnitState.GetCurrentStat(eStat_HP),, 'UniqueTraits');
			SyncState(UnitState);
			`log("UniqueTraits [DIAG] : purchase hook done -- mobility" @ UnitState.GetCurrentStat(eStat_Mobility) @ "dodge" @ UnitState.GetCurrentStat(eStat_Dodge) @ "aim" @ UnitState.GetCurrentStat(eStat_Offense) @ "HP" @ UnitState.GetCurrentStat(eStat_HP),, 'UniqueTraits');
			return;
		}
	}
}

// <Ability:UT_PredestinedNote/> (CHL #419, UT_TraitBase.ExpandAbilityTag): the effect of the perk's symbol for the soldier shown in the popup, at the end of the text, or nothing.
static function bool ExpandAbilityTag(string InString, out string OutString, Object ParseObj, Object StrategyParseObj, XComGameState GameState)
{
	if (!(InString ~= "UT_PredestinedNote"))
		return false;

	OutString = BuildNote(ParseObj, StrategyParseObj);

	return true;
}

// %VALUE = what a perk of Symbol gives now (Previous perks of the symbol are already chosen), %BASE = the first one's bonus, %STEP = the increase per perk chosen before.
static final function string FillBonus(string Text, int Symbol, int Previous)
{
	local string Result;

	Result = Repl(Text, "%VALUE", string(GetSymbolBonus(Symbol, Previous)));
	Result = Repl(Result, "%BASE", string(GetSymbolBonus(Symbol, 0)));
	Result = Repl(Result, "%STEP", string(GetSymbolBonus(Symbol, 1) - GetSymbolBonus(Symbol, 0)));
	Result = Repl(Result, "%ABL", string(default.PREDESTINED_HP_ABLATIVE_BONUS + default.PREDESTINED_HP_ABLATIVE_STEP * Previous));

	return Result;
}

// %LIM = the number of perks of the same symbol from which the perk gives points instead of a stat (the limit + 1), %AP = those points, %PCT = their share of the purple symbol's.
static final function string FillOverflow(string Text, XComGameState_Unit Unit, int Column)
{
	local string Result;

	Result = Repl(Text, "%LIM", string(default.PREDESTINED_ESCALATION_LIMIT + 1));
	Result = Repl(Result, "%AP", string(GetOverflowAP(Unit, Column)));
	Result = Repl(Result, "%PCT", string(default.PREDESTINED_OVERFLOW_AP_PCT));

	return Result;
}

static final function string BuildNote(Object ParseObj, Object StrategyParseObj)
{
	local XComGameState_Unit Unit;
	local XComGameState_Ability AbilityState;
	local name AbilityName;
	local array<int> Rows;
	local int Column, Row, Symbol;
	local string Note;

	Unit = XComGameState_Unit(StrategyParseObj);
	if (Unit == none || !IsReady(Unit) || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Predestined'))
		return "";

	if (X2AbilityTemplate(ParseObj) != none)
	{
		AbilityName = X2AbilityTemplate(ParseObj).DataName;
	}
	else
	{
		AbilityState = XComGameState_Ability(ParseObj);
		if (AbilityState == none)
			return "";
		AbilityName = AbilityState.GetMyTemplateName();
	}

	for (Column = 1; Column <= GetColumnCount(Unit); ++Column)
	{
		Rows = class'UT_Trait_SomeoneDifferent'.static.GetEvolutionCandidates(Unit, Column);
		for (Row = 0; Row < Rows.Length; ++Row)
		{
			if (Unit.AbilityTree[Column].Abilities[Rows[Row]].AbilityName != AbilityName)
				continue;

			Symbol = GetSymbol(Unit, Column, Rows[Row]);
			if (Symbol != SYMBOL_DIAMOND && Symbol != 0 && CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]) >= default.PREDESTINED_ESCALATION_LIMIT)
			{
				return "\n\n" $ FillOverflow(default.PREDESTINED_NOTE_OVERFLOW, Unit, Column);
			}

			switch (Symbol)
			{
				case SYMBOL_DIAMOND:
					`log("UniqueTraits [DIAG] : Predestined diamond --" @ Unit.GetFullName() @ "class" @ Unit.GetSoldierClassTemplateName() @ "hero" @ Unit.IsResistanceHero() @ "rank" @ Unit.GetRank() @ "ComInt" @ int(Unit.ComInt) @ "column" @ Column
						@ "class base AP" @ Unit.GetSoldierClassTemplate().BaseAbilityPointsPerPromotion @ "soldier AP" @ Unit.GetBaseSoldierAPAmount(Unit.ComInt) @ "level AP" @ GetLevelAP(Unit, Column) @ "diamond AP" @ GetDiamondAP(Unit, Column),, 'UniqueTraits');
					Note =Repl(default.PREDESTINED_NOTE_DIAMOND, "%AP", string(GetDiamondAP(Unit, Column)));
					break;
				case SYMBOL_WAVES:
					Note = Repl(default.PREDESTINED_NOTE_WAVES, "%AP", string(GetWavesAP(Unit, Column)));
					Note = FillBonus(Note, Symbol, CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]));
					break;
				case SYMBOL_BANDS:
					Note = FillBonus(default.PREDESTINED_NOTE_BANDS, Symbol, CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]));
					break;
				case SYMBOL_CROSS:
					Note = FillBonus(default.PREDESTINED_NOTE_CROSS, Symbol, CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]));
					break;
				case SYMBOL_SQUARE:
					Note = FillBonus(default.PREDESTINED_NOTE_SQUARE, Symbol, CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]));
					break;
				case SYMBOL_CIRCLE:
					Note = FillBonus(default.PREDESTINED_NOTE_CIRCLE, Symbol, CountPreviousSymbol(Unit, Symbol, Column, Rows[Row]));
					break;
			}

			// A symbol other than the diamond: what the perk gives while fewer perks of its symbol than the limit were chosen (the text above), then what it gives instead afterwards.
			if (Note != "" && Symbol != SYMBOL_DIAMOND)
				Note = FillOverflow(Note $ " " $ default.PREDESTINED_NOTE_TAIL, Unit, Column);

			if (Note != "")
				return "\n\n" $ Note;
		}
	}

	return "";
}
