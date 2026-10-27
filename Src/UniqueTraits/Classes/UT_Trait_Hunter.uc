//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Hunter.uc
//  PURPOSE: Hunter: enemies detect this soldier from farther away (detection malus on the ability), and while the soldier is CONCEALED he gets
//           +HUNTER_CONCEALED_SIGHT_BONUS Sight Radius (the raw stat, like the Scout's malus; the stat is in meters and a tile is 1.5 m). The sight bonus is an effect of the hidden ability UT_HunterVision applied "by hand"
//           (UT_EffectHelpers) when the soldier is concealed at the start of the mission ('StartOfMatchConcealment') or enters concealment later
//           ('UnitConcealmentEntered'); bRemoveWhenTargetConcealmentBroken takes it off when the concealment breaks (like the officer's Lightning Strike).
//---------------------------------------------------------------------------------------
class UT_Trait_Hunter extends UT_TraitBase config(UniqueTraits);

var config int HUNTER_CONCEALED_SIGHT_BONUS;

var config float HUNTER_DETECTION_MODIFIER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Hunter());
	Templates.AddItem(HunterVision());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	Template.AddCHEvent('StartOfMatchConcealment', OnStartOfMatchConcealment_Hunter, ELD_OnStateSubmitted, 50);
	Template.AddCHEvent('UnitConcealmentEntered', OnUnitConcealmentEntered_Hunter, ELD_OnStateSubmitted, 50);
}

// Hunter: enemy detection range grows (malus). The sight bonus while concealed is HunterVision, applied by the listeners below.
static function X2AbilityTemplate Hunter()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = PurePassive('UT_Hunter', "img:///UniqueTraits_Icons.UT_Hunter", true);

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Hunter_Detection';
	StatEffect.BuildPersistentEffect(1, true, false);
	StatEffect.SetDisplayInfo(ePerkBuff_Penalty, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	// eStat_DetectionModifier is what OTHER units apply against this one (their radius * (1 - modifier)),
	// so a negative value widens the radius at which enemies spot this soldier.
	StatEffect.AddPersistentStatChange(eStat_DetectionModifier, default.HUNTER_DETECTION_MODIFIER);
	Template.AddTargetEffect(StatEffect);

	return Template;
}

// Hidden ability (never granted): holds the sight bonus while concealed.
static function X2AbilityTemplate HunterVision()
{
	local X2AbilityTemplate Template;
	local X2Effect_PersistentStatChange StatEffect;

	Template = HiddenEffectHolder('UT_HunterVision');

	StatEffect = new class'X2Effect_PersistentStatChange';
	StatEffect.EffectName = 'UT_Hunter_Vision';
	StatEffect.DuplicateResponse = eDupe_Ignore;
	StatEffect.BuildPersistentEffect(1, true, true, false, eGameRule_PlayerTurnEnd);
	StatEffect.bRemoveWhenTargetConcealmentBroken = true;
	StatEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), "img:///UniqueTraits_Icons.UT_Hunter", true,, Template.AbilitySourceName);
	StatEffect.AddPersistentStatChange(eStat_SightRadius, default.HUNTER_CONCEALED_SIGHT_BONUS);
	Template.AddTargetEffect(StatEffect);

	return Template;
}

// 'StartOfMatchConcealment' (EventSource = the XCOM player, ELD_OnStateSubmitted: the units are concealed in the history by now): every Hunter of the squad.
static function EventListenerReturn OnStartOfMatchConcealment_Hunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local array<int> UnitIDs;
	local int UnitID;

	PlayerState = XComGameState_Player(EventSource);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	// The ids first: submitting a state while walking a list of the history is not safe.
	foreach XComHQ.Squad(SquadRef)
		UnitIDs.AddItem(SquadRef.ObjectID);

	foreach UnitIDs(UnitID)
		GrantConcealedSight(UnitID);

	return ELR_NoInterrupt;
}

// 'UnitConcealmentEntered' (EventSource = the unit): a Hunter that gets concealed again (Shadow, Phantom...).
static function EventListenerReturn OnUnitConcealmentEntered_Hunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Unit Unit;

	Unit = XComGameState_Unit(EventSource);
	if (Unit != none)
		GrantConcealedSight(Unit.ObjectID);

	return ELR_NoInterrupt;
}

// Gives the sight bonus to the unit if it holds the trait, is concealed and does not have the bonus yet (both events can fire for the same unit).
static function GrantConcealedSight(int UnitID)
{
	local XComGameStateHistory History;
	local XComGameState_Unit Unit, MutableUnit;
	local XComGameState NewGameState;

	History = `XCOMHISTORY;
	Unit = XComGameState_Unit(History.GetGameStateForObjectID(UnitID));
	if (Unit == none || !Unit.IsAlive() || Unit.bRemovedFromPlay || !Unit.IsConcealed() || Unit.IsUnitAffectedByEffectName('UT_Hunter_Vision')
		|| !class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Hunter'))
		return;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Hunter concealed sight");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitID));
	if (class'UT_EffectHelpers'.static.ApplyAbilityEffect('UT_HunterVision', 0, MutableUnit, MutableUnit, NewGameState) != 'AA_Success')
	{
		History.CleanupPendingGameState(NewGameState);
		return;
	}

	// The sight radius changed: the visibility of the map must be recomputed.
	MutableUnit.bRequiresVisibilityUpdate = true;
	`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
}
