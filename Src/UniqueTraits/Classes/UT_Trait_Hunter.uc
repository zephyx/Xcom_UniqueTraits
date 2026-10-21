//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_Hunter.uc
//  PURPOSE: Hunter: detection malus here; the 'hear the enemies' bonus is the 'PlayerTurnEnded' listener.
//---------------------------------------------------------------------------------------
class UT_Trait_Hunter extends UT_TraitBase config(UniqueTraits);

var config int HUNTER_HEARING_INTERVAL;

var config float HUNTER_DETECTION_MODIFIER;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(Hunter());

	return Templates;
}

// Event registrations (X2EventListener_UniqueTraits.CreateTacticalListeners calls this for every trait of the pool that is not disabled).
static function OnCreateTacticalListeners(CHEventListenerTemplate Template)
{
	Template.AddCHEvent('PlayerTurnEnded', OnPlayerTurnEnded_Hunter, ELD_OnStateSubmitted, 50);
}

// Hunter: enemy detection range grows (malus). The "hear the enemies" bonus is event-driven, see
// UT_Trait_Hunter.OnPlayerTurnEnded_Hunter.
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

// Hunter: while a Hunter is alive on the mission, the squad "hears" the nearest enemy pod every
// HUNTER_HEARING_INTERVAL turns without having seen an enemy => vanilla's own hidden-movement
// indicator (X2Action_HiddenMovement), which normally only starts after TurnsUntilIndicator (a
// GameCore.ini value) such turns. Skipped once vanilla's own indicator is active so it never plays
// twice in one turn-end. Which soldier the camera/sound centre on is vanilla's native choice (the
// human closest to the pods), not necessarily the Hunter.
static function EventListenerReturn OnPlayerTurnEnded_Hunter(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState_Player PlayerState;
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference SquadRef;
	local XComGameState_Unit SquadUnit;
	local XComGameState NewGameState;
	local bool bHunterAlive;

	PlayerState = XComGameState_Player(EventData);
	if (PlayerState == none || PlayerState.GetTeam() != eTeam_XCom)
		return ELR_NoInterrupt;

	if (default.HUNTER_HEARING_INTERVAL <= 0
		|| PlayerState.TurnsSinceEnemySeen <= 0
		|| PlayerState.TurnsSinceEnemySeen % default.HUNTER_HEARING_INTERVAL != 0
		|| PlayerState.TurnsSinceEnemySeen >= class'X2Action_HiddenMovement'.default.TurnsUntilIndicator)
		return ELR_NoInterrupt;

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none)
		return ELR_NoInterrupt;

	foreach XComHQ.Squad(SquadRef)
	{
		SquadUnit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(SquadRef.ObjectID));
		if (SquadUnit != none && SquadUnit.IsAlive() && !SquadUnit.bRemovedFromPlay
			&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SquadUnit, 'UT_Hunter'))
		{
			bHunterAlive = true;
			break;
		}
	}
	if (!bHunterAlive)
		return ELR_NoInterrupt;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UniqueTraits: Hunter hearing");
	// A game state with no modified object can be dropped before its visualization is built.
	NewGameState.ModifyStateObject(class'XComGameState_Player', PlayerState.ObjectID);
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualization_HunterHearing;
	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

static function BuildVisualization_HunterHearing(XComGameState VisualizeGameState)
{
	class'X2Action_HiddenMovement'.static.AddHiddenMovementActionToBlock(VisualizeGameState);
}
