//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Smoker.uc
//  PURPOSE: Smoker [LWOTC ONLY]: free smoke grenades here; "no turn end" is X2AbilityCost_UT_SmokeThrow, will gain and fatigue doubling are listeners.
//---------------------------------------------------------------------------------------
class UT_Trait_Smoker extends UT_TraitBase config(UniqueTraits);

var config int SMOKER_WILL_REGEN;
var config int SMOKER_FATIGUE_INTERVAL_NORMAL, SMOKER_FATIGUE_INTERVAL_TIRED;
var config WillEventRollData SMOKER_FATIGUE_ROLL_DATA;

var config name SMOKER_GRENADE_ITEM_NAME;
var config int SMOKER_GRENADE_COUNT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Smoker());

	return Templates;
}

// Smoker: 2 free smoke grenades. "Doesn't end turn when thrown" is
// X2AbilityCost_UT_SmokeThrow, spliced into the shared ThrowGrenade template by
// UT_Trait_Smoker.OnPostTemplatesCreated. Regain Will when
// standing near the smoke grenade impact and the fatigue-doubling malus are both handled by
// UT_Trait_Smoker.OnPlayerTurnEnded_Smoker.
static function X2AbilityTemplate Smoker()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_TemporaryItem GrenadeEffect;

	Template = PurePassive('UT_Smoker', "img:///UILibrary_PerkIcons.UIPerk_standard", true);

	GrenadeEffect = new class'X2Effect_UT_TemporaryItem';
	GrenadeEffect.EffectName = 'UT_Smoker_FreeSmokeGrenades';
	GrenadeEffect.ItemName = default.SMOKER_GRENADE_ITEM_NAME;
	GrenadeEffect.ItemInventorySlot = eInvSlot_Utility;
	GrenadeEffect.Quantity = default.SMOKER_GRENADE_COUNT;
	// One icon with a stack of N (added to any smoke grenade the holder already carries) instead of N separate icons.
	GrenadeEffect.bStackOnExisting = true;
	GrenadeEffect.BuildPersistentEffect(1, true, false);
	GrenadeEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(GrenadeEffect);

	return Template;
}

// Smoker's will gain: a ONE-TIME +SMOKER_WILL_REGEN Will per smoke grenade, granted only to a
// Smoker trait holder who is standing exactly where a smoke grenade (any thrower) lands, at the
// moment it detonates.
static function EventListenerReturn OnAbilityActivated_Smoker(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateContext_Ability AbilityContext;
	local XComGameState_Ability AbilityState;
	local XComGameState_Item SourceWeapon;
	local StateObjectReference TargetRef;
	local XComGameState_Unit TargetUnit, MutableUnit;
	local XComGameState NewGameState;
	local int NewWill;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
		return ELR_NoInterrupt;

	AbilityContext = XComGameStateContext_Ability(GameState.GetContext());
	if (AbilityContext == none)
		return ELR_NoInterrupt;

	AbilityState = XComGameState_Ability(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.AbilityRef.ObjectID));
	if (AbilityState == none
		|| (AbilityState.GetMyTemplateName() != 'ThrowGrenade' && AbilityState.GetMyTemplateName() != 'LaunchGrenade'))
		return ELR_NoInterrupt;

	SourceWeapon = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(AbilityContext.InputContext.ItemObject.ObjectID));
	if (SourceWeapon == none
		|| class'X2AbilityCost_UT_SmokeThrow'.default.SMOKER_GRENADE_WEAPON_NAMES.Find(SourceWeapon.GetMyTemplateName()) == INDEX_NONE)
		return ELR_NoInterrupt;

	foreach AbilityContext.InputContext.MultiTargets(TargetRef)
	{
		TargetUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(TargetRef.ObjectID));
		if (TargetUnit == none || TargetUnit.IsDead()
			|| !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(TargetUnit, 'UT_Smoker'))
			continue;

		NewWill = Min(TargetUnit.GetCurrentStat(eStat_Will) + default.SMOKER_WILL_REGEN, TargetUnit.GetMaxStat(eStat_Will));
		if (NewWill <= TargetUnit.GetCurrentStat(eStat_Will))
			continue;

		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Smoker will gain");
		MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', TargetUnit.ObjectID));
		MutableUnit.SetCurrentStat(eStat_Will, NewWill);
		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

// Fatigue-doubling malus.
// LWOTC's own per-turn will loss (X2EventListener_Tactical.RollForPerTurnWillLoss,
// LW_Overhaul) can't be referenced or hooked directly. LW_Overhaul is a separate,
// independently-compiled mod package this project has no compile-time visibility into, and
// every LWOTC-gated trait must not introduce a hard dependency on it. Instead, this performs a
// second, independent will roll for each holder on the exact same public vanilla/CHL primitive
// LWOTC's own listener uses (XComGameStateContext_WillRoll, config(GameCore), unconditionally
// available), on a cadence mirroring LWOTC's own default config (NUM_TURNS_FOR_WILL_LOSS=3 /
// NUM_TURNS_FOR_TIRED_WILL_LOSS=2, PerTurnWillRollData / see XComLW_Overhaul.ini) via this
// mod's own, independently configurable copy of those values. The two rolls are entirely
// independent (this one doesn't read or affect LWOTC's own), so the net effect for a holder is
// losing will on this cadence roughly twice as often as a normal squadmate => "doubles" in the
// practical, felt sense described by the trait, without literally being coupled to LWOTC's
// internal implementation.
static function EventListenerReturn OnPlayerTurnEnded_Smoker(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit;
	local XComGameStateContext_WillRoll WillRollContext;
	local int Interval;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit == none)
			continue;

		if (!class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Smoker'))
			continue;

		Interval = (SquadUnit.GetMentalState() == eMentalState_Tired) ? default.SMOKER_FATIGUE_INTERVAL_TIRED : default.SMOKER_FATIGUE_INTERVAL_NORMAL;
		if (Interval <= 0 || PlayerState.PlayerTurnCount % Interval != 0)
			continue;

		if (class'XComGameStateContext_WillRoll'.static.ShouldPerformWillRoll(default.SMOKER_FATIGUE_ROLL_DATA, SquadUnit))
		{
			WillRollContext = class'XComGameStateContext_WillRoll'.static.CreateWillRollContext(SquadUnit, 'UT_ExtraFatigue',, false);
			WillRollContext.DoWillRoll(default.SMOKER_FATIGUE_ROLL_DATA);
			WillRollContext.Submit();
		}
	}

	return ELR_NoInterrupt;
}

static function OnPostTemplatesCreated()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2AbilityTemplate ThrowGrenadeTemplate;
	local X2AbilityCost_ActionPoints OriginalCost;
	local X2AbilityCost_UT_SmokeThrow NewCost;
	local int i;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	ThrowGrenadeTemplate = AbilityManager.FindAbilityTemplate('ThrowGrenade');
	if (ThrowGrenadeTemplate == none)
		return;

	for (i = 0; i < ThrowGrenadeTemplate.AbilityCosts.Length; ++i)
	{
		OriginalCost = X2AbilityCost_ActionPoints(ThrowGrenadeTemplate.AbilityCosts[i]);
		if (OriginalCost == none)
			continue;

		NewCost = new class'X2AbilityCost_UT_SmokeThrow';
		NewCost.iNumPoints = OriginalCost.iNumPoints;
		NewCost.bFreeCost = OriginalCost.bFreeCost;
		NewCost.bAddWeaponTypicalCost = OriginalCost.bAddWeaponTypicalCost;
		NewCost.bConsumeAllPoints = OriginalCost.bConsumeAllPoints;
		NewCost.bMoveCost = OriginalCost.bMoveCost;
		NewCost.AllowedTypes = OriginalCost.AllowedTypes;
		NewCost.DoNotConsumeAllEffects = OriginalCost.DoNotConsumeAllEffects;
		NewCost.DoNotConsumeAllSoldierAbilities = OriginalCost.DoNotConsumeAllSoldierAbilities;

		ThrowGrenadeTemplate.AbilityCosts[i] = NewCost;
		break;
	}
}
