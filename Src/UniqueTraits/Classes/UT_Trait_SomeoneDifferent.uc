//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_SomeoneDifferent.uc
//  PURPOSE: Someone different: the soldier escaped from an alien laboratory and gets sicker with each rank, then mutates. Needs Community Promotion
//           Screen (RequiredMods in the ini: the evolutions are marked on the promotion screen, see UT_PromotionMarks). Three phases:
//           1. SICKNESS (rookie -> sergeant): fixed stat maluses per rank (SOMEONEDIFFERENT_STAGES_*: totals, not increments; the highest stage whose
//              rank is reached applies). The LAST stage is the "sergeant" stage: from its rank on the soldier is ripe for phase 2. Two tables, LWOTC
//              (Lance Corporal, Corporal, Sergeant = ranks 2, 3, 4) and the base game (Corporal, Sergeant = ranks 2, 3).
//           2. COLLAPSE (first mission of a ripe soldier): at the start of his SOMEONEDIFFERENT_KNOCKOUT_TURN-th XCOM turn he falls unconscious (the
//              game's own Unconscious effect, applied by hand from the hidden ability UT_SomeoneDifferentKnockout) with a red flyover; if he comes
//              round (Revival Protocol, Restorative Mist...) another flyover says so. UnitValue UT_SD_Knocked remembers that the TRAIT put him down.
//              A mission that never reaches that turn changes nothing: it happens again on a later mission, whatever his rank (>= sergeant).
//           3. MUTATION (OnPostMission, once the mission is over, also for a captured soldier): the sickness maluses are taken back, the soldier is
//              respecced (the game's own respec; with LWOTC a mirror of LWOTC's RespecSoldier, see RespecUnit), receives the passive UT_Mutant and
//              one random "evolution" ability per promotion column but the squaddie one (UnitValues UT_SD_Evo_<column> = row + 1, drawn on the tree AFTER
//              the respec because LWOTC's respec rebuilds it; class rows only, never the pistol / XCOM rows, see GetClassRowCount). The larger the SHARE of the
//              evolutions available at his rank that he bought, the stronger: the percentage SOMEONEDIFFERENT_PCT_LOW[chosen] / _HIGH[not chosen], scaled to a
//              scale of the number of evolution columns (7 with LWOTC, 6 in the base game; GetTargetPercent), is applied to HP, mobility, aim, will, dodge, hacking and psi offense
//              (permanent stat changes, SyncStats) and to the direct damage of his attacks (X2Effect_UT_Mutant, UnitValue UT_SD_DamagePct).
//           Every stat change is a diff against what is already applied (UT_SD_Applied_<stat>), so it is idempotent and OnClear takes back exactly
//           that. There is no hook on an ability purchase: SyncStats runs on rank-up, after a respec, at mission start and when the promotion screen
//           closes (UIScreenListener_UT_PromotionMarks.OnRemoved).
//---------------------------------------------------------------------------------------
class UT_Trait_SomeoneDifferent extends UT_TraitBase config(UniqueTraits);

struct SDStage
{
	var int RankReached;                                       // the stage applies from this soldier rank on
	var int WillMalus, AimMalus, MobilityMalus, HPMalus;       // positive numbers: total points lost at this stage
};

var config array<SDStage> SOMEONEDIFFERENT_STAGES_LWOTC, SOMEONEDIFFERENT_STAGES_BASEGAME;
var config int SOMEONEDIFFERENT_KNOCKOUT_TURN, SOMEONEDIFFERENT_BASEGAME_CLASS_ROWS;
var config array<int> SOMEONEDIFFERENT_PCT_LOW;                // percentage by number of evolutions chosen, out of the evolution columns, 7 with LWOTC and 6 in the base game (index 0, 1, 2...)
var config array<int> SOMEONEDIFFERENT_PCT_HIGH;               // percentage by number of evolutions NOT chosen, out of the evolution columns (index 0, 1...)
var localized string SOMEONEDIFFERENT_FLYOVER_SICK, SOMEONEDIFFERENT_FLYOVER_RECOVER;

const MAX_EVOLUTION_COLUMNS = 16;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PurePassive('UT_SomeoneDifferent', "img:///UniqueTraits_Icons.UT_SomeoneDifferent", true));
	Templates.AddItem(Mutant());
	Templates.AddItem(SomeoneDifferentKnockout());

	return Templates;
}

// Given at the mutation (never in the ini's GrantedAbilities): the damage percentage; the stats are permanent changes (SyncStats).
static function X2AbilityTemplate Mutant()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_Mutant DamageEffect;

	Template = PurePassive('UT_Mutant', "img:///UniqueTraits_Icons.UT_SomeoneDifferent_2", true);

	DamageEffect = new class'X2Effect_UT_Mutant';
	DamageEffect.EffectName = 'UT_Mutant_Damage';
	DamageEffect.BuildPersistentEffect(1, true, false);
	DamageEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(DamageEffect);

	return Template;
}

// Holder of the unconscious effect applied by hand at phase 2 (hidden, never granted). It is the game's own Unconscious effect (same EffectName, so
// the Revival Protocol / Restorative Mist / medikit still remove it) with our flyovers.
static function X2AbilityTemplate SomeoneDifferentKnockout()
{
	local X2AbilityTemplate Template;
	local X2Effect_Persistent KnockoutEffect;

	Template = HiddenEffectHolder('UT_SomeoneDifferentKnockout');

	KnockoutEffect = class'X2StatusEffects'.static.CreateUnconsciousStatusEffect();
	KnockoutEffect.VisualizationFn = KnockoutVisualization_SomeoneDifferent;
	KnockoutEffect.EffectRemovedVisualizationFn = RecoverVisualization_SomeoneDifferent;
	KnockoutEffect.CleansedVisualizationFn = RecoverVisualization_SomeoneDifferent;
	Template.AddTargetEffect(KnockoutEffect);

	return Template;
}

//---------------------------------------------------------------------------------------
// State of the soldier
//---------------------------------------------------------------------------------------

static final function bool IsMutated(XComGameState_Unit Unit)
{
	return GetUnitFloat(Unit, 'UT_SD_Mutated') > 0;
}

static final function array<SDStage> GetStages()
{
	if (class'UniqueTraits_TraitConfig'.static.IsModActive('LongWarOfTheChosen'))
		return default.SOMEONEDIFFERENT_STAGES_LWOTC;

	return default.SOMEONEDIFFERENT_STAGES_BASEGAME;
}

// The "sergeant" rank: the rank of the last stage. 99 (never) without any stage in the ini.
static final function int GetSergeantRank()
{
	local array<SDStage> Stages;

	Stages = GetStages();
	if (Stages.Length == 0)
		return 99;

	return Stages[Stages.Length - 1].RankReached;
}

// The stage that applies to a soldier of rank Rank: the one with the highest RankReached <= Rank. False below the first stage.
static final function bool GetStageForRank(int Rank, out SDStage Stage)
{
	local array<SDStage> Stages;
	local int i, BestRank;
	local bool bFound;

	Stages = GetStages();
	BestRank = -1;
	for (i = 0; i < Stages.Length; ++i)
	{
		if (Stages[i].RankReached <= Rank && Stages[i].RankReached > BestRank)
		{
			BestRank = Stages[i].RankReached;
			Stage = Stages[i];
			bFound = true;
		}
	}

	return bFound;
}

// For the Mod Config Menu options (UniqueTraits_MCMOptions): a field (0 will, 1 aim, 2 mobility, 3 health) of a stage of the sickness tables. The struct type SDStage is
// not used outside this class (a struct of one of our classes cannot be used from another), hence these helpers.
static final function int GetStageField(bool bLWOTC, int Stage, int Field)
{
	local array<SDStage> Stages;

	if (bLWOTC)
		Stages = default.SOMEONEDIFFERENT_STAGES_LWOTC;
	else
		Stages = default.SOMEONEDIFFERENT_STAGES_BASEGAME;

	if (Stage < 0 || Stage >= Stages.Length)
		return 0;

	switch (Field)
	{
		case 0:
			return Stages[Stage].WillMalus;
		case 1:
			return Stages[Stage].AimMalus;
		case 2:
			return Stages[Stage].MobilityMalus;
		case 3:
			return Stages[Stage].HPMalus;
	}

	return 0;
}

static final function SetStageField(bool bLWOTC, int Stage, int Field, int Value)
{
	if (bLWOTC)
	{
		if (Stage < 0 || Stage >= default.SOMEONEDIFFERENT_STAGES_LWOTC.Length)
			return;

		switch (Field)
		{
			case 0:
				default.SOMEONEDIFFERENT_STAGES_LWOTC[Stage].WillMalus = Value;
				break;
			case 1:
				default.SOMEONEDIFFERENT_STAGES_LWOTC[Stage].AimMalus = Value;
				break;
			case 2:
				default.SOMEONEDIFFERENT_STAGES_LWOTC[Stage].MobilityMalus = Value;
				break;
			case 3:
				default.SOMEONEDIFFERENT_STAGES_LWOTC[Stage].HPMalus = Value;
				break;
		}
	}
	else
	{
		if (Stage < 0 || Stage >= default.SOMEONEDIFFERENT_STAGES_BASEGAME.Length)
			return;

		switch (Field)
		{
			case 0:
				default.SOMEONEDIFFERENT_STAGES_BASEGAME[Stage].WillMalus = Value;
				break;
			case 1:
				default.SOMEONEDIFFERENT_STAGES_BASEGAME[Stage].AimMalus = Value;
				break;
			case 2:
				default.SOMEONEDIFFERENT_STAGES_BASEGAME[Stage].MobilityMalus = Value;
				break;
			case 3:
				default.SOMEONEDIFFERENT_STAGES_BASEGAME[Stage].HPMalus = Value;
				break;
		}
	}
}

// Number of promotion columns that carry an evolution: all of them but the squaddie one (7 with LWOTC, 6 in the base game).
static final function int GetEvolutionColumns(XComGameState_Unit Unit)
{
	return Clamp(Unit.AbilityTree.Length - 1, 0, MAX_EVOLUTION_COLUMNS);
}

// How many rows of a column are CLASS abilities. The ability tree holds every row of the
// class template's slots in order: the class rows come first, then the XCOM row (a slot filled from a random deck) and LWOTC's pistol row (eInvSlot_Pistol), so
// the count stops at the first slot of either kind (LWOTC: usually 3 class rows). The base game has 2 class rows (SOMEONEDIFFERENT_BASEGAME_CLASS_ROWS):
// a mod can add an XCOM row there that is not recognizable by its slot.
static final function int GetClassRowCount(XComGameState_Unit Unit, int Column)
{
	local X2SoldierClassTemplate ClassTemplate;
	local array<SoldierClassAbilitySlot> Slots;
	local int Count;

	ClassTemplate = Unit.GetSoldierClassTemplate();
	if (ClassTemplate == none || Column < 0 || Column >= Unit.AbilityTree.Length)
		return 0;

	Slots = ClassTemplate.GetAbilitySlots(Column);
	while (Count < Slots.Length && Slots[Count].RandomDeckName == '' && Slots[Count].AbilityType.ApplyToWeaponSlot != eInvSlot_Pistol)
		++Count;

	if (!class'UniqueTraits_TraitConfig'.static.IsModActive('LongWarOfTheChosen'))
		Count = Min(Count, default.SOMEONEDIFFERENT_BASEGAME_CLASS_ROWS);

	return Min(Count, Unit.AbilityTree[Column].Abilities.Length);
}

// The row (index in the column's abilities) of the evolution of Column, INDEX_NONE if there is none.
static final function int GetEvolutionRow(XComGameState_Unit Unit, int Column)
{
	return int(GetUnitFloat(Unit, name("UT_SD_Evo_" $ Column))) - 1;
}

// The drawn row is still a class ability of the column (a save made before the class rows rule, or a tree rebuilt by another mod, can hold anything).
static final function bool IsEvolutionValid(XComGameState_Unit Unit, int Column)
{
	local int Row;

	Row = GetEvolutionRow(Unit, Column);

	return Row >= 0 && Row < GetClassRowCount(Unit, Column) && Unit.AbilityTree[Column].Abilities[Row].AbilityName != '';
}

// The rows of Column that can carry the evolution: the class rows that hold an ability.
static final function array<int> GetEvolutionCandidates(XComGameState_Unit Unit, int Column)
{
	local array<int> Rows;
	local int i, RowCount;

	RowCount = GetClassRowCount(Unit, Column);
	for (i = 0; i < RowCount; ++i)
	{
		if (Unit.AbilityTree[Column].Abilities[i].AbilityName != '')
			Rows.AddItem(i);
	}

	return Rows;
}

// A column needs a (new) evolution when it has none that is valid although it could have one.
static final function bool NeedsEvolution(XComGameState_Unit Unit, int Column)
{
	local array<int> Rows;

	if (IsEvolutionValid(Unit, Column))
		return false;

	Rows = GetEvolutionCandidates(Unit, Column);

	return Rows.Length > 0;
}

// Draws the evolution of Column among its class rows. The unit must be modifiable.
static final function DrawEvolution(XComGameState_Unit MutableUnit, int Column)
{
	local array<int> Rows;

	MutableUnit.ClearUnitValue(name("UT_SD_Evo_" $ Column));
	Rows = GetEvolutionCandidates(MutableUnit, Column);
	if (Rows.Length > 0)
		MutableUnit.SetUnitFloatValue(name("UT_SD_Evo_" $ Column), Rows[`SYNC_RAND_STATIC(Rows.Length)] + 1, eCleanup_Never);
}

// True when the soldier bought the evolution of Column.
static final function bool HasBoughtEvolution(XComGameState_Unit Unit, int Column)
{
	local int Row, i;

	Row = GetEvolutionRow(Unit, Column);
	if (Row < 0)
		return false;

	for (i = 0; i < Unit.m_SoldierProgressionAbilties.Length; ++i)
	{
		if (Unit.m_SoldierProgressionAbilties[i].iRank == Column && Unit.m_SoldierProgressionAbilties[i].iBranch == Row)
			return true;
	}

	return false;
}

// How many evolutions the soldier could have bought so far and how many he did: only the columns his rank has reached count (column C opens at
// rank C + 1: a base game Sergeant, rank 3, has 2 evolutions available, a LWOTC Sergeant, rank 4, has 3).
static final function CountEvolutions(XComGameState_Unit Unit, out int Available, out int Chosen)
{
	local int Column;

	Available = 0;
	Chosen = 0;
	for (Column = 1; Column <= GetEvolutionColumns(Unit) && Column < Unit.GetRank(); ++Column)
	{
		if (!IsEvolutionValid(Unit, Column))
			continue;

		++Available;
		if (HasBoughtEvolution(Unit, Column))
			++Chosen;
	}
}

// The percentage the mutation calls for (stats and damage): 0 until the mutation. It depends on the SHARE of the available evolutions that were chosen, not
// on their number: the share is scaled to the number of evolution columns (7 with LWOTC, 6 in the base game: the tables are written
// as fractions of it), and the usual rule applies (PCT_LOW[chosen], PCT_HIGH[missing], else 0). Scaling never gives the lowest step to
// a soldier who chose one, nor the highest to one who missed one. Half of them chosen, for instance, is 3.5 / 7 (3 / 6): no change.
static final function int GetTargetPercent(XComGameState_Unit Unit)
{
	local int Available, Chosen, Scaled, Missing, Reference;

	if (!IsMutated(Unit))
		return 0;

	CountEvolutions(Unit, Available, Chosen);
	if (Available <= 0)
		return 0;

	Reference = GetEvolutionColumns(Unit);
	if (Reference <= 0)
		return 0;

	Scaled = Round(float(Chosen) * Reference / Available);
	if (Chosen < Available)
		Scaled = Min(Scaled, Reference - 1);
	if (Chosen > 0)
		Scaled = Max(Scaled, 1);

	Missing = Reference - Scaled;
	if (Scaled < default.SOMEONEDIFFERENT_PCT_LOW.Length)
		return default.SOMEONEDIFFERENT_PCT_LOW[Scaled];
	if (Missing < default.SOMEONEDIFFERENT_PCT_HIGH.Length)
		return default.SOMEONEDIFFERENT_PCT_HIGH[Missing];

	return 0;
}

//---------------------------------------------------------------------------------------
// Stats
//---------------------------------------------------------------------------------------

static final function array<ECharStatType> GetAffectedStats()
{
	local array<ECharStatType> Stats;

	Stats.AddItem(eStat_HP);
	Stats.AddItem(eStat_Mobility);
	Stats.AddItem(eStat_Offense);
	Stats.AddItem(eStat_Will);
	Stats.AddItem(eStat_Dodge);
	Stats.AddItem(eStat_Hacking);
	Stats.AddItem(eStat_PsiOffense);

	return Stats;
}

static final function name AppliedValueName(ECharStatType Stat)
{
	return name("UT_SD_Applied_" $ int(Stat));
}

// The net change currently applied to the soldier for a stat (what OnClear takes back).
static final function int GetAppliedShift(XComGameState_Unit Unit, ECharStatType Stat)
{
	return int(GetUnitFloat(Unit, AppliedValueName(Stat)));
}

// Phase 1: the fixed malus of the soldier's rank (a negative number), none once mutated.
static final function int GetTargetMalus(XComGameState_Unit Unit, ECharStatType Stat)
{
	local SDStage Stage;

	if (IsMutated(Unit) || !GetStageForRank(Unit.GetRank(), Stage))
		return 0;

	switch (Stat)
	{
		case eStat_Will:
			return -Stage.WillMalus;
		case eStat_Offense:
			return -Stage.AimMalus;
		case eStat_Mobility:
			return -Stage.MobilityMalus;
		case eStat_HP:
			return -Stage.HPMalus;
	}

	return 0;
}

// The net change a stat should have: the phase 1 malus, or the mutation's percentage of the stat WITHOUT our own change (the reference). HP and
// mobility never go below 1 (the others not below 0).
static final function int GetTargetShift(XComGameState_Unit Unit, ECharStatType Stat)
{
	local float Reference;
	local int Shift, MinValue;

	Reference = Unit.GetMaxStat(Stat) - GetAppliedShift(Unit, Stat);
	Shift = GetTargetMalus(Unit, Stat) + Round(Reference * GetTargetPercent(Unit) / 100.0);

	MinValue = (Stat == eStat_HP || Stat == eStat_Mobility) ? 1 : 0;
	if (Shift < 0 && Reference + Shift < MinValue)
		Shift = Min(0, MinValue - int(Reference));

	return Shift;
}

static final function bool NeedsSync(XComGameState_Unit Unit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;
	local int Column;

	if (IsMutated(Unit))
	{
		for (Column = 1; Column <= GetEvolutionColumns(Unit); ++Column)
		{
			if (NeedsEvolution(Unit, Column))
				return true;
		}
	}

	Stats = GetAffectedStats();
	foreach Stats(Stat)
	{
		if (GetTargetShift(Unit, Stat) != GetAppliedShift(Unit, Stat))
			return true;
	}

	return GetUnitFloat(Unit, 'UT_SD_DamagePct') != GetTargetPercent(Unit);
}

// Brings the stats and the damage percentage to what the soldier's rank / evolutions call for. The unit must be modifiable (a pending state object).
static final function bool SyncStats(XComGameState_Unit MutableUnit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;
	local int TargetShift, Applied, Percent, Column;
	local bool bChanged;

	// A respec since the last shift: the ledger is forgotten, so are the marks of what was applied.
	if (ForgetIfRespec(MutableUnit))
		OnStatsWiped(MutableUnit);

	// An evolution that is missing or no longer a class ability (a mutation made before the class rows rule, a tree rebuilt by another mod) is drawn again.
	if (IsMutated(MutableUnit))
	{
		for (Column = 1; Column <= GetEvolutionColumns(MutableUnit); ++Column)
		{
			if (NeedsEvolution(MutableUnit, Column))
			{
				DrawEvolution(MutableUnit, Column);
				bChanged = true;
			}
		}
	}

	Stats = GetAffectedStats();
	foreach Stats(Stat)
	{
		TargetShift = GetTargetShift(MutableUnit, Stat);
		Applied = GetAppliedShift(MutableUnit, Stat);
		if (TargetShift == Applied)
			continue;

		ShiftStat(MutableUnit, Stat, TargetShift - Applied);
		MutableUnit.SetUnitFloatValue(AppliedValueName(Stat), TargetShift, eCleanup_Never);
		if (Stat == eStat_HP && MutableUnit.GetCurrentStat(eStat_HP) < 1)
			MutableUnit.SetCurrentStat(eStat_HP, 1);
		bChanged = true;
	}

	Percent = GetTargetPercent(MutableUnit);
	if (GetUnitFloat(MutableUnit, 'UT_SD_DamagePct') != Percent)
	{
		MutableUnit.SetUnitFloatValue('UT_SD_DamagePct', Percent, eCleanup_Never);
		bChanged = true;
	}

	if (bChanged)
		`log("UniqueTraits : Someone different --" @ MutableUnit.GetFullName() @ "rank" @ MutableUnit.GetRank() @ "mutated" @ IsMutated(MutableUnit) @ "percent" @ Percent
			@ "HP" @ GetAppliedShift(MutableUnit, eStat_HP) $ ", mobility" @ GetAppliedShift(MutableUnit, eStat_Mobility) $ ", aim" @ GetAppliedShift(MutableUnit, eStat_Offense)
			$ ", will" @ GetAppliedShift(MutableUnit, eStat_Will),, 'UniqueTraits');

	return bChanged;
}

// Takes back every stat change currently applied (exactly what ShiftStat put in: the ledger; the unit's values are left at 0).
static final function TakeBackStats(XComGameState_Unit MutableUnit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;

	RevertShifts(MutableUnit);

	Stats = GetAffectedStats();
	foreach Stats(Stat)
		MutableUnit.ClearUnitValue(AppliedValueName(Stat));
	MutableUnit.ClearUnitValue('UT_SD_DamagePct');
}

static function bool ShiftsStats()
{
	return true;
}

// The base stats were rebuilt by a respec (LWOTC's RespecSoldier on a holder; the mutation's own respec does not come here): the shifts are gone with them.
// The marks go to zero without touching the stats and SyncStats applies the stage again (it also draws again an evolution the rebuilt tree lost).
static function OnStatsReset(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	OnStatsWiped(MutableUnit);
	SyncStats(MutableUnit);
}

// The ledger and the marks of what was applied go; the stats are not touched.
static function OnStatsWiped(XComGameState_Unit MutableUnit)
{
	local array<ECharStatType> Stats;
	local ECharStatType Stat;

	ForgetShifts(MutableUnit);
	Stats = GetAffectedStats();
	foreach Stats(Stat)
		MutableUnit.ClearUnitValue(AppliedValueName(Stat));
}

static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	// Defensive: a unit that had the trait before was cleared by OnClear. A soldier who is already ranked (AddUniqueTrait) gets the malus of his rank.
	ClearTraitValues(MutableUnit);
	SyncStats(MutableUnit);
}

// The trait is already out of AcquiredTraits here, so nothing may depend on UnitHasTrait.
static function OnClear(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local int i;

	TakeBackStats(MutableUnit);
	ClearTraitValues(MutableUnit);

	for (i = MutableUnit.AWCAbilities.Length - 1; i >= 0; --i)
	{
		if (MutableUnit.AWCAbilities[i].AbilityType.AbilityName == 'UT_Mutant')
			MutableUnit.AWCAbilities.Remove(i, 1);
	}
}

static final function ClearTraitValues(XComGameState_Unit MutableUnit)
{
	local int Column;

	MutableUnit.ClearUnitValue('UT_SD_Mutated');
	MutableUnit.ClearUnitValue('UT_SD_Knocked');
	for (Column = 1; Column <= MAX_EVOLUTION_COLUMNS; ++Column)
		MutableUnit.ClearUnitValue(name("UT_SD_Evo_" $ Column));
}

//---------------------------------------------------------------------------------------
// Sync points
//---------------------------------------------------------------------------------------

// 'UnitRankUp' (EventData = the unit) and 'CompleteRespecSoldier' (EventSource = the unit), both ELD_OnStateSubmitted: the change is committed, the sync
// goes in a transaction of its own.
static function EventListenerReturn OnStatsMayHaveChanged_SomeoneDifferent(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Unit;

	Unit = XComGameState_Unit(EventData);
	if (Unit == none)
		Unit = XComGameState_Unit(EventSource);
	if (Unit != none)
		SyncUnit(Unit.GetReference());

	return ELR_NoInterrupt;
}

// A transaction of its own, only when something has to change (also called when the promotion screen closes, where the evolutions are bought).
static final function SyncUnit(StateObjectReference UnitRef)
{
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState NewGameState;

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_SomeoneDifferent') || !NeedsSync(Unit))
		return;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Someone different stats sync");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
	SyncStats(MutableUnit);
	`GAMERULES.SubmitGameState(NewGameState);
}

// Mission start (the point that guarantees the stats in combat): the squad's holders are synced in the mission's own state.
static function EventListenerReturn OnTacticalBeginPlay_SomeoneDifferent(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
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
		if (SquadUnit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_SomeoneDifferent') || !NeedsSync(SquadUnit))
			continue;

		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', SquadUnit.ObjectID));
		SyncStats(MutableUnit);
	}

	return ELR_NoInterrupt;
}

//---------------------------------------------------------------------------------------
// Phase 2: the collapse
//---------------------------------------------------------------------------------------

// 'PlayerTurnBegun' (EventData = the player, whose turn counter was already incremented by the turn's own state), ELD_OnStateSubmitted: from the
// SOMEONEDIFFERENT_KNOCKOUT_TURN-th XCOM turn on, every ripe holder of the squad who was not put down yet falls unconscious (a soldier who was not
// in play at that turn, or who was already down, is caught at a later turn).
static function EventListenerReturn OnPlayerTurnBegun_SomeoneDifferent(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit, MutableUnit;
	local array<int> UnitIDs;
	local XComGameState NewGameState;
	local int UnitID, Applied;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom || PlayerState.PlayerTurnCount < default.SOMEONEDIFFERENT_KNOCKOUT_TURN)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(History.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit != none && SquadUnit.IsAlive() && !SquadUnit.bRemovedFromPlay && !SquadUnit.IsIncapacitated()
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_SomeoneDifferent')
			&& !IsMutated(SquadUnit) && GetUnitFloat(SquadUnit, 'UT_SD_Knocked') <= 0 && SquadUnit.GetRank() >= GetSergeantRank())
		{
			UnitIDs.AddItem(SquadUnit.ObjectID);
		}
	}

	if (UnitIDs.Length == 0)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Someone different collapse");
	foreach UnitIDs(UnitID)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitID));
		if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_SomeoneDifferentKnockout', 0, MutableUnit, MutableUnit, NewGameState) == 'AA_Success')
		{
			MutableUnit.SetUnitFloatValue('UT_SD_Knocked', 1, eCleanup_Never);
			++Applied;
		}
	}

	if (Applied == 0)
	{
		History.CleanupPendingGameState(NewGameState);
		return ELR_NoInterrupt;
	}

	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_Knockout;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_Knockout(XComGameState VisualizeGameState)
{
	class'UT_EffectHelpers'.static.AddEffectVisualization(VisualizeGameState, 'UT_SomeoneDifferentKnockout', 0);
}

// The effect's VisualizationFn (called by AddEffectVisualization): the red flyover, the game's own "Unconscious" flyover and message, then the soldier lies down.
static function KnockoutVisualization_SomeoneDifferent(XComGameState VisualizeGameState, out VisualizationActionMetadata ActionMetadata, const name EffectApplyResult)
{
	local X2Action_PersistentEffect PersistentEffectAction;

	if (EffectApplyResult != 'AA_Success' || XComGameState_Unit(ActionMetadata.StateObject_NewState) == none)
		return;

	// Camera on the soldier, as for the other incapacitating effects.
	class'X2StatusEffects'.static.AddEffectCameraPanToAffectedUnitToTrack(ActionMetadata, VisualizeGameState.GetContext());
	class'X2StatusEffects'.static.AddEffectSoundAndFlyOverToTrack(ActionMetadata, VisualizeGameState.GetContext(), default.SOMEONEDIFFERENT_FLYOVER_SICK, '', eColor_Bad);

	// The fall: what a unit that becomes unconscious (or bleeds out) from damage plays (XGUnitNativeBase.BuildAbilityEffectsVisualization). X2Action_Knockout
	// is not it: it needs an ability context and only serves the Knockout ability.
	PersistentEffectAction = X2Action_PersistentEffect(class'X2Action_PersistentEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	PersistentEffectAction.IdleAnimName = '';
	class'X2Action_Death'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded);

	// The game's own "Unconscious" flyover, message and unit flag.
	class'X2StatusEffects'.static.UnconsciousVisualization(VisualizeGameState, ActionMetadata, EffectApplyResult);
}

// The game's own "back on his feet" visualization, then the flyover (only if the soldier really is up: the game's one returns early when he is dead / still down).
static function RecoverVisualization_SomeoneDifferent(XComGameState VisualizeGameState, out VisualizationActionMetadata ActionMetadata, const name EffectApplyResult)
{
	local XComGameState_Unit UnitState;

	class'X2StatusEffects'.static.UnconsciousVisualizationRemoved(VisualizeGameState, ActionMetadata, EffectApplyResult);

	UnitState = XComGameState_Unit(ActionMetadata.StateObject_NewState);
	if (UnitState != none && !UnitState.IsDead() && !UnitState.IsIncapacitated() && !UnitState.bRemovedFromPlay)
		class'X2StatusEffects'.static.AddEffectSoundAndFlyOverToTrack(ActionMetadata, VisualizeGameState.GetContext(), default.SOMEONEDIFFERENT_FLYOVER_RECOVER, '', eColor_Attention);
}

//---------------------------------------------------------------------------------------
// Phase 3: the mutation
//---------------------------------------------------------------------------------------

// UT_TraitBase.OnPostMission: every living holder (also a captured one: he will be back already mutated) that the trait put down during the mission.
static function OnPostMission()
{
	local XComGameState_Unit Unit, MutableUnit;
	local array<int> UnitIDs;
	local XComGameState NewGameState;
	local int UnitID;

	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (Unit.IsSoldier() && Unit.IsAlive() && GetUnitFloat(Unit, 'UT_SD_Knocked') > 0 && !IsMutated(Unit)
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_SomeoneDifferent'))
		{
			UnitIDs.AddItem(Unit.ObjectID);
		}
	}

	if (UnitIDs.Length == 0)
		return;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Someone different mutation");
	foreach UnitIDs(UnitID)
	{
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitID));
		MutateUnit(MutableUnit, NewGameState);
	}
	`GAMERULES.SubmitGameState(NewGameState);
}

static final function MutateUnit(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local ClassAgnosticAbility AWCAbility;
	local int Column, i;
	local bool bHasMutant;

	`log("UniqueTraits : Someone different -- mutation of" @ MutableUnit.GetFullName() @ "(rank" @ MutableUnit.GetRank() $ ")",, 'UniqueTraits');

	// 1. The sickness goes away (the stats are clean again before the respec).
	TakeBackStats(MutableUnit);
	MutableUnit.ClearUnitValue('UT_SD_Knocked');

	// 2. Respec of every ability.
	RespecUnit(MutableUnit, NewGameState);

	// 3. One random evolution per column but the squaddie one, among the CLASS rows of the tree as it is AFTER the respec (see GetClassRowCount).
	MutableUnit.SetUnitFloatValue('UT_SD_Mutated', 1, eCleanup_Never);
	for (Column = 1; Column <= MAX_EVOLUTION_COLUMNS; ++Column)
		MutableUnit.ClearUnitValue(name("UT_SD_Evo_" $ Column));

	for (Column = 1; Column <= GetEvolutionColumns(MutableUnit); ++Column)
		DrawEvolution(MutableUnit, Column);

	// 4. The passive "Mutant".
	for (i = 0; i < MutableUnit.AWCAbilities.Length; ++i)
	{
		if (MutableUnit.AWCAbilities[i].AbilityType.AbilityName == 'UT_Mutant')
			bHasMutant = true;
	}
	if (!bHasMutant)
	{
		AWCAbility.AbilityType.AbilityName = 'UT_Mutant';
		AWCAbility.AbilityType.ApplyToWeaponSlot = eInvSlot_Unknown;
		AWCAbility.AbilityType.UtilityCat = '';
		AWCAbility.iRank = 0;
		AWCAbility.bUnlocked = true;
		MutableUnit.AWCAbilities.AddItem(AWCAbility);
	}

	// 5. Nothing bought yet: the stats start at the lowest percentage.
	SyncStats(MutableUnit);
}

// Respec of the soldier's abilities, keeping his rank and his stats. Without LWOTC: the base game's respec (X2 XComGameStateContext_HeadquartersOrder.
// CompleteRespecSoldier): the abilities go, the squaddie ones come back, the spent ability points are refunded. With LWOTC: a mirror of LWOTC's
// RespecSoldier (X2DownloadableContentInfo_LongWarOfTheChosen, which cannot be called from here, see the soft-dependency rule): ability points and rank
// reset, then the soldier ranks up again to his rank, which rebuilds the ability tree and gives back the points of each rank. LWOTC also puts back the
// unit's stored randomized initial stats; the stats the soldier had are restored instead, which is the same thing.
static final function RespecUnit(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	local array<float> SavedMax, SavedCurrent;
	local name ClassName;
	local int i, NumRanks;
	local bool bWasRankedUp, bHadPopup;

	if (!class'UniqueTraits_TraitConfig'.static.IsModActive('LongWarOfTheChosen'))
	{
		MutableUnit.ResetSoldierAbilities();
		for (i = 0; i < MutableUnit.GetRankAbilityCount(0); ++i)
			MutableUnit.BuySoldierProgressionAbility(NewGameState, 0, i);

		MutableUnit.AbilityPoints += MutableUnit.SpentAbilityPoints;
		MutableUnit.SpentAbilityPoints = 0;
		return;
	}

	ClassName = MutableUnit.GetSoldierClassTemplateName();
	NumRanks = MutableUnit.GetRank();
	bWasRankedUp = MutableUnit.bRankedUp;
	bHadPopup = MutableUnit.bNeedsNewClassPopup;

	for (i = 0; i < eStat_MAX; ++i)
	{
		SavedMax.AddItem(MutableUnit.GetMaxStat(ECharStatType(i)));
		SavedCurrent.AddItem(MutableUnit.GetCurrentStat(ECharStatType(i)));
	}

	MutableUnit.AbilityPoints = 0;
	MutableUnit.SpentAbilityPoints = 0;
	MutableUnit.ResetSoldierRank();
	MutableUnit.ComInt = eComInt_Gifted;   // what LWOTC does ("Average": LWOTC renamed the base game's Gifted)
	MutableUnit.ResetSoldierAbilities();
	MutableUnit.ClearUnitValue('LWOTC_AbilityCostModifier');
	for (i = 0; i < NumRanks; ++i)
		MutableUnit.RankUpSoldier(NewGameState, ClassName);

	for (i = 0; i < eStat_MAX; ++i)
	{
		MutableUnit.SetBaseMaxStat(ECharStatType(i), SavedMax[i]);
		MutableUnit.SetCurrentStat(ECharStatType(i), SavedCurrent[i]);
	}

	// The rank-ups just replayed must not count as a new promotion nor show the "new class" popup again.
	MutableUnit.bRankedUp = bWasRankedUp;
	MutableUnit.bNeedsNewClassPopup = bHadPopup;
}
