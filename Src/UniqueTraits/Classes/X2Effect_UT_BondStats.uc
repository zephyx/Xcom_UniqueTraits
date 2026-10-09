//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_BondStats.uc
//  PURPOSE: Psychic Bond's stats: for the mission, the holder and his bondmate (the vanilla soldier bond) each get, for every base stat (HP,
//           aim, mobility, will, dodge, psi offense, hacking), the best BASE value of the two (GetBaseStat: what items and armor bring is not
//           counted). The effect is a mission-scoped stat change computed when it is applied (OnEffectAdded), from the bondmate's stats.
//           bPartnerSide = false: the holder's own effect (also applies the partner's effect to the bondmate, which is not a trait holder);
//           bPartnerSide = true: the bondmate's effect, applied by the holder's one (never recursive).
//           Only applies if the bondmate is deployed in the same mission.
//---------------------------------------------------------------------------------------
class X2Effect_UT_BondStats extends X2Effect_PersistentStatChange;

var bool bPartnerSide;

simulated protected function AddBestChange(XComGameState_Effect NewEffectState, ECharStatType StatType, XComGameState_Unit Unit, XComGameState_Unit Mate)
{
	local StatChange Change;
	local float Gain;

	Gain = Mate.GetBaseStat(StatType) - Unit.GetBaseStat(StatType);
	if (Gain <= 0)
		return;

	Change.StatType = StatType;
	Change.StatAmount = Gain;
	Change.ModOp = MODOP_Addition;
	NewEffectState.StatChanges.AddItem(Change);
}

// The deployed bondmate of Unit, or none (no bond, not in this mission, dead).
static function XComGameState_Unit FindDeployedBondmate(XComGameState_Unit Unit, XComGameState NewGameState, optional out string Reason)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference MateRef;
	local XComGameState_Unit Mate;

	if (Unit == none || !Unit.HasSoldierBond(MateRef))
	{
		Reason = "no soldier bond";
		return none;
	}

	XComHQ = XComGameState_HeadquartersXCom(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));
	if (XComHQ == none || !XComHQ.IsUnitInSquad(MateRef))
	{
		Reason = "bondmate" @ MateRef.ObjectID @ "is not in the squad";
		return none;
	}

	if (NewGameState != none)
		Mate = XComGameState_Unit(NewGameState.GetGameStateForObjectID(MateRef.ObjectID));
	if (Mate == none)
		Mate = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(MateRef.ObjectID));

	if (Mate == none || !Mate.IsAlive())
	{
		Reason = "bondmate not found or dead";
		return none;
	}

	return Mate;
}

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit Unit, Mate, MutableMate;
	local X2AbilityTemplate PartnerTemplate;
	local EffectAppliedData PartnerData;
	local string Reason;
	local int i;

	Unit = XComGameState_Unit(kNewTargetState);
	Mate = FindDeployedBondmate(Unit, NewGameState, Reason);

	NewEffectState.StatChanges.Length = 0;
	if (Mate != none)
	{
		AddBestChange(NewEffectState, eStat_HP, Unit, Mate);
		AddBestChange(NewEffectState, eStat_Offense, Unit, Mate);
		AddBestChange(NewEffectState, eStat_Mobility, Unit, Mate);
		AddBestChange(NewEffectState, eStat_Will, Unit, Mate);
		AddBestChange(NewEffectState, eStat_Dodge, Unit, Mate);
		AddBestChange(NewEffectState, eStat_PsiOffense, Unit, Mate);
		AddBestChange(NewEffectState, eStat_Hacking, Unit, Mate);
	}

	`log("UniqueTraits : Psychic Bond --" @ Unit.GetFullName() @ (bPartnerSide ? "(bondmate's side)" : "(holder)") @ "| bondmate:" @ (Mate != none ? Mate.GetFullName() : "none (" $ Reason $ ")")
		@ "| stat changes:" @ NewEffectState.StatChanges.Length,, 'UniqueTraits');
	for (i = 0; i < NewEffectState.StatChanges.Length; ++i)
		`log("UniqueTraits : Psychic Bond --   stat" @ NewEffectState.StatChanges[i].StatType @ "+" $ NewEffectState.StatChanges[i].StatAmount,, 'UniqueTraits');

	// Skip X2Effect_PersistentStatChange's own OnEffectAdded (it would overwrite StatChanges with the fixed list) and go straight to the one
	// that applies them. With nothing to add, X2Effect_ModifyStats would only raise a redscreen.
	if (NewEffectState.StatChanges.Length > 0)
		super(X2Effect_ModifyStats).OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);

	// The holder's effect also gives the bondmate the best stats (the bondmate is not a trait holder, so he has no ability of his own).
	if (!bPartnerSide && Mate != none)
	{
		PartnerTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate('UT_PsychicBondPartner');
		if (PartnerTemplate != none && PartnerTemplate.AbilityTargetEffects.Length > 0)
		{
			MutableMate = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Mate.ObjectID));

			PartnerData = ApplyEffectParameters;
			PartnerData.TargetStateObjectRef = MutableMate.GetReference();
			PartnerData.EffectRef.SourceTemplateName = 'UT_PsychicBondPartner';
			PartnerData.EffectRef.LookupType = TELT_AbilityTargetEffects;
			PartnerData.EffectRef.TemplateEffectLookupArrayIndex = 0;
			PartnerData.EffectRef.ApplyOnTickIndex = INDEX_NONE;

			PartnerTemplate.AbilityTargetEffects[0].ApplyEffect(PartnerData, MutableMate, NewGameState);
		}
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
