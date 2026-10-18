//---------------------------------------------------------------------------------------
//  FILE:   UT_Trait_PsychicBond.uc
//  PURPOSE: Psychic Bond: the holder and his bondmate (the vanilla soldier bond; ignored when he has none or the bondmate is not deployed) get,
//           at the start of every mission, the best BASE stats of the two (X2Effect_UT_BondStats; the HP gain is granted as ablative protection,
//           not as HP), and when one of them loses health the other
//           loses PSYCHICBOND_SHARED_DAMAGE_PCT % of it too (two soldiers in the same 10-damage explosion each end with 15).
//           - Stats: the holder's passive effect (UT_PsychicBond) also applies the partner's effect, the effect of the hidden ability
//             UT_PsychicBondPartner (an effect applied by hand must come from an ability template), to the bondmate.
//           - Damage: 'UnitTakeEffectDamage' (ELD_OnStateSubmitted, the share is a state of its own). The shared loss is taken with
//             ModifyCurrentStat, which fires no event (no ping-pong between the two) and cannot kill: it never brings the bondmate below 1 HP.
//---------------------------------------------------------------------------------------
class UT_Trait_PsychicBond extends UT_TraitBase config(UniqueTraits);

var config int PSYCHICBOND_SHARED_DAMAGE_PCT;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(PsychicBond());
	Templates.AddItem(PsychicBondPartner());

	return Templates;
}

static function X2AbilityTemplate PsychicBond()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_BondStats BondEffect;

	Template = PurePassive('UT_PsychicBond', "img:///UniqueTraits_Icons.UT_PsychicBond", true);

	BondEffect = new class'X2Effect_UT_BondStats';
	BondEffect.EffectName = 'UT_PsychicBond_Stats';
	BondEffect.bPartnerSide = false;
	BondEffect.BuildPersistentEffect(1, true, false);
	BondEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, false,, Template.AbilitySourceName);
	Template.AddTargetEffect(BondEffect);

	return Template;
}

// Holder of the bondmate's stat effect (hidden, never granted); its name and description are shown on the bondmate.
static function X2AbilityTemplate PsychicBondPartner()
{
	local X2AbilityTemplate Template;
	local X2Effect_UT_BondStats PartnerEffect;

	Template = HiddenEffectHolder('UT_PsychicBondPartner');

	PartnerEffect = new class'X2Effect_UT_BondStats';
	PartnerEffect.EffectName = 'UT_PsychicBond_PartnerStats';
	PartnerEffect.bPartnerSide = true;
	PartnerEffect.BuildPersistentEffect(1, true, false);
	PartnerEffect.SetDisplayInfo(ePerkBuff_Bonus, Template.LocFriendlyName, Template.GetMyLongDescription(), Template.IconImage, true,, Template.AbilitySourceName);
	Template.AddTargetEffect(PartnerEffect);

	return Template;
}

// 'UnitTakeEffectDamage' (ELD_OnStateSubmitted): the unit's damage results since the last time they were shared (a per-unit marker: the number of
// results already handled, UnitValue UT_PsychicBond_Handled) are added up and, if the unit and its bondmate are a Psychic Bond pair (either one
// holds the trait), the bondmate loses a share of them. Works from the unit's LATEST state in the history, not from the event's source object.
static function EventListenerReturn OnUnitTakeEffectDamage_PsychicBond(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameStateHistory History;
	local XComGameState_Unit Unit, Mate, MutableUnit, MutableMate;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState NewGameState;
	local StateObjectReference MateRef;
	local UnitValue Handled;
	local int i, Lost, Share, NewHP, FromIndex;

	if (XComGameState_Unit(EventSource) == none)
		return ELR_NoInterrupt;

	History = `XCOMHISTORY;
	Unit = XComGameState_Unit(History.GetGameStateForObjectID(XComGameState_Unit(EventSource).ObjectID));
	if (Unit == none || Unit.DamageResults.Length == 0)
		return ELR_NoInterrupt;

	Unit.GetUnitValue('UT_PsychicBond_Handled', Handled);
	FromIndex = Clamp(int(Handled.fValue), 0, Unit.DamageResults.Length);
	if (FromIndex == Unit.DamageResults.Length)
		return ELR_NoInterrupt;

	for (i = FromIndex; i < Unit.DamageResults.Length; ++i)
		Lost += Unit.DamageResults[i].DamageAmount;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Psychic Bond: shared damage");
	MutableUnit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
	MutableUnit.SetUnitFloatValue('UT_PsychicBond_Handled', Unit.DamageResults.Length, eCleanup_BeginTactical);

	if (Lost > 0 && Unit.HasSoldierBond(MateRef))
	{
		XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
		Mate = XComGameState_Unit(History.GetGameStateForObjectID(MateRef.ObjectID));
		if (XComHQ != none && XComHQ.IsUnitInSquad(MateRef) && Mate != none && Mate.IsAlive()
			&& (class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_PsychicBond') || class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Mate, 'UT_PsychicBond')))
		{
			Share = Round(Lost * default.PSYCHICBOND_SHARED_DAMAGE_PCT / 100.0);
			MutableMate = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Mate.ObjectID));
			NewHP = Max(1, int(MutableMate.GetCurrentStat(eStat_HP)) - Share);
			if (Share > 0 && NewHP < int(MutableMate.GetCurrentStat(eStat_HP)))
			{
				MutableMate.ModifyCurrentStat(eStat_HP, NewHP - int(MutableMate.GetCurrentStat(eStat_HP)));

				// LowestHP, from which the end-of-mission wound is sized, is only updated by the game in TakeEffectDamage (ModifyCurrentStat leaves
				// it alone): without this the shared damage healed itself at the end of the mission (the bondmate came back unwounded).
				if (MutableMate.GetCurrentStat(eStat_HP) < MutableMate.LowestHP)
					MutableMate.LowestHP = int(MutableMate.GetCurrentStat(eStat_HP));

				`log("UniqueTraits : Psychic Bond --" @ Unit.GetFullName() @ "lost" @ Lost @ "HP, bondmate" @ MutableMate.GetFullName() @ "loses" @ Share @ "(now" @ NewHP $ ")",, 'UniqueTraits');
			}
		}
	}

	`GAMERULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}
