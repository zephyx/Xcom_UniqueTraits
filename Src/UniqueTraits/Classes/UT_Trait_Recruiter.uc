//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Recruiter.uc
//  PURPOSE: Recruiter [LWOTC ONLY: "haven adviser" is LWOTC's liaison]: -RECRUITER_DODGE_MALUS dodge. At the end of every month, with
//           X% chance (X = the share of the past month he spent stationed as haven adviser, UT_LWOTCHelpers.GetLiaisonRegion) one
//           more soldier recruit joins the Resistance's recruitable pool, and with Y% = X * RECRUITER_ROOKIE_CHANCE_FACTOR (half) a
//           free rookie joins the XCOM roster; the two rolls are independent.
//           Time as adviser is tracked on the holder in UnitValues (hours of the game clock, UT_Recruiter_Hours = this month's total,
//           UT_Recruiter_Mark = clock of the running interval or -1, UT_Recruiter_MonthStart): updated by SyncLiaisonTime when the staff
//           changes ('StaffUpdated') and at the end of the month.
//           Built with the vanilla recruit creation only (XComGameState_HeadquartersResistance.RefillRecruits / GiveRecruit): doubling
//           the recruit RATE of an LWOTC haven would need LW_Overhaul's job classes.
//---------------------------------------------------------------------------------------
class UT_Trait_Recruiter extends UT_TraitBase config(UniqueTraits);

var config int RECRUITER_DODGE_MALUS;
var config float RECRUITER_ROOKIE_CHANCE_FACTOR;
var localized string RECRUITER_ROOKIE_NOTICE;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Recruiter());

	return Templates;
}

// Recruiter: -20 dodge (a plain stat effect, like Athlete's). The monthly recruits are OnPreEndOfMonth_Recruiter.
static function X2AbilityTemplate Recruiter()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Recruiter', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Recruiter';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Passive, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_Dodge, -default.RECRUITER_DODGE_MALUS);
	Template.AddTargetEffect(StatEffect);

	Template.SetUIStatMarkup(class'XLocalizedData'.default.DodgeLabel, eStat_Dodge, -default.RECRUITER_DODGE_MALUS);

	return Template;
}

// The game clock in hours since a fixed date (all that matters are differences).
static final function int GetNowHours()
{
	local TDateTime Base;

	class'X2StrategyGameRulesetDataStructures'.static.SetTime(Base, 0, 0, 0, 1, 1, 2000);
	return class'X2StrategyGameRulesetDataStructures'.static.DifferenceInHours(`STRATEGYRULES.GameTime, Base);
}

// Closes the running interval (up to now) and opens a new one if the unit is a haven adviser NOW. Unit must be modifiable. Call it whenever
// the adviser status may have changed (before the change is taken into account: the interval that ends now was spent in the old status).
static final function SyncLiaisonTime(XComGameState_Unit Unit)
{
	local float Mark, Hours;
	local int Now;

	Now = GetNowHours();
	Mark = GetUnitFloat(Unit, 'UT_Recruiter_Mark', -1);
	Hours = GetUnitFloat(Unit, 'UT_Recruiter_Hours', 0);

	if (Mark >= 0)
		Hours += Now - Mark;

	Unit.SetUnitFloatValue('UT_Recruiter_Hours', Hours, eCleanup_Never);
	Unit.SetUnitFloatValue('UT_Recruiter_Mark', class'UT_LWOTCHelpers'.static.GetLiaisonRegion(Unit) != none ? float(Now) : -1.0, eCleanup_Never);
}

// A new month of tracking begins for the new holder (a soldier who already is a haven adviser counts from now).
static function OnGrant(XComGameState_Unit MutableUnit, XComGameState NewGameState)
{
	MutableUnit.SetUnitFloatValue('UT_Recruiter_Hours', 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue('UT_Recruiter_Mark', -1, eCleanup_Never);
	SyncLiaisonTime(MutableUnit);
	MutableUnit.SetUnitFloatValue('UT_Recruiter_MonthStart', GetNowHours(), eCleanup_Never);
}

static function OnClear(XComGameState_Unit MutableUnit)
{
	MutableUnit.SetUnitFloatValue('UT_Recruiter_Hours', 0, eCleanup_Never);
	MutableUnit.SetUnitFloatValue('UT_Recruiter_Mark', -1, eCleanup_Never);
	MutableUnit.SetUnitFloatValue('UT_Recruiter_MonthStart', 0, eCleanup_Never);
}

// 'StaffUpdated' (a staff slot, incl. LWOTC's haven liaison slots, was filled or emptied): keeps the tracked time up to date.
static function EventListenerReturn OnStaffUpdated_Recruiter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit;
	local XComGameState NewGameState;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_Recruiter'))
			continue;

		if (NewGameState == none)
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Recruiter adviser time");
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		SyncLiaisonTime(MutableUnit);
	}

	if (NewGameState != none)
		`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// A new soldier made the way vanilla's own RefillRecruits makes the monthly recruits.
static final function XComGameState_Unit CreateRecruit(XComGameState NewGameState)
{
	local XComGameState_Unit Recruit;

	Recruit = `CHARACTERPOOLMGR.CreateCharacter(NewGameState, `XPROFILESETTINGS.Data.m_eCharPoolUsage);
	Recruit.RandomizeStats();
	if (!Recruit.HasBackground())
		Recruit.GenerateBackground();
	Recruit.ApplyInventoryLoadout(NewGameState);

	// LWOTC fires this for every soldier it creates (nationality...): no class of LW_Overhaul is referenced, only the event name.
	`XEVENTMGR.TriggerEvent('SoldierCreatedEvent', Recruit, Recruit, NewGameState);

	return Recruit;
}

// 'PreEndOfMonth' (CHL #539, with the pending end-of-month game state, BEFORE vanilla's RefillRecruits: the recruits added here stay in the
// pool, RefillRecruits keeps the existing ones).
static function EventListenerReturn OnPreEndOfMonth_Recruiter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersResistance ResistanceHQ;
	local array<XComGameState_Unit> Soldiers;
	local XComGameState_Unit Soldier, MutableUnit, NewSoldier;
	local float Hours, MonthHours, SharePct, RookiePct;
	local int Now;

	if (GameState == none)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	ResistanceHQ = XComGameState_HeadquartersResistance(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersResistance'));
	if (XComHQ == none || ResistanceHQ == none)
		return ELR_NoInterrupt;

	Now = GetNowHours();

	Soldiers = XComHQ.GetSoldiers();
	foreach Soldiers(Soldier)
	{
		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Soldier, 'UT_Recruiter'))
			continue;

		// Close the running interval, read this month's total and start a new month.
		MutableUnit = XComGameState_Unit(GameState.ModifyStateObject(class'XComGameState_Unit', Soldier.ObjectID));
		SyncLiaisonTime(MutableUnit);
		Hours = GetUnitFloat(MutableUnit, 'UT_Recruiter_Hours', 0);
		MonthHours = Now - GetUnitFloat(MutableUnit, 'UT_Recruiter_MonthStart', Now);
		MutableUnit.SetUnitFloatValue('UT_Recruiter_Hours', 0, eCleanup_Never);
		MutableUnit.SetUnitFloatValue('UT_Recruiter_MonthStart', Now, eCleanup_Never);

		SharePct = (MonthHours > 0) ? FClamp(Hours / MonthHours, 0.0, 1.0) * 100.0 : 0.0;
		RookiePct = SharePct * default.RECRUITER_ROOKIE_CHANCE_FACTOR;
		`log("UniqueTraits : Recruiter --" @ Soldier.GetFullName() @ ": adviser for" @ Hours @ "h of" @ MonthHours @ "h => recruit chance" @ SharePct $ "%, rookie chance" @ RookiePct $ "%",, 'UniqueTraits');

		if (`SYNC_FRAND_STATIC() * 100.0 < SharePct)
		{
			ResistanceHQ = XComGameState_HeadquartersResistance(GameState.ModifyStateObject(class'XComGameState_HeadquartersResistance', ResistanceHQ.ObjectID));
			NewSoldier = CreateRecruit(GameState);
			ResistanceHQ.Recruits.AddItem(NewSoldier.GetReference());
			`log("UniqueTraits : Recruiter -- a recruit was added to the recruitable pool",, 'UniqueTraits');
		}

		if (`SYNC_FRAND_STATIC() * 100.0 < RookiePct)
		{
			// A free rookie straight into the roster, as GiveRecruit does when a recruit is hired without delay.
			XComHQ = XComGameState_HeadquartersXCom(GameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
			NewSoldier = CreateRecruit(GameState);
			NewSoldier.ApplyBestGearLoadout(GameState);
			XComHQ.AddToCrew(GameState, NewSoldier);
			XComHQ.HandlePowerOrStaffingChange(GameState);

			`log("UniqueTraits : Recruiter -- a free rookie joined the roster:" @ NewSoldier.GetFullName(),, 'UniqueTraits');

			// Geoscape notice, the way vanilla announces a healed soldier (XComGameState_HeadquartersProjectHealSoldier.OnProjectCompleted).
			`HQPRES.Notify(Repl(default.RECRUITER_ROOKIE_NOTICE, "%UNIT", NewSoldier.GetName(eNameType_RankFull)), class'UIUtilities_Image'.const.EventQueue_Staff);
		}
	}

	return ELR_NoInterrupt;
}
