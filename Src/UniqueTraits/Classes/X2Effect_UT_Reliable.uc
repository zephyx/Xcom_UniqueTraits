//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Reliable.uc
//  PURPOSE: Reliable's three rules, on the holder as ATTACKER:
//           1. he never makes a critical hit: the crit chance of his shots is zeroed in the hit table (below), and ChangeHitResultForAttacker turns any
//              critical result that still comes out (an ability that guarantees crits, bHitsAreCrits) into a plain hit;
//           2. the crit chance of the shot is converted into aim: +ceil(crit / RELIABLE_CRIT_TO_AIM_DIVISOR) (2) on the hit chance;
//           3. the target's dodge (the Graze entry of the table) is reduced by RELIABLE_DODGE_REDUCTION_PCT % (100) of that crit chance, never below 0.
//           The dodge cut is the whole crit chance, and the WHOLE crit chance of the shot is converted (base stat, weapon, perks,
//           flanking, bonuses given by the target...), not only the bonuses above the base stat.
//
//           HOW (read this before touching the delegate):
//           - The total crit chance of a shot only exists once EVERY modifier is in (attacker effects, target effects, reaction fire...), so it is read in CHL's
//             OverrideFinalHitChanceFns (#555) delegate, which FinalizeHitChance calls first with the complete table. The delegate receives no unit, so
//             GetToHitModifiers (called only on the attacker's own effects, i.e. only for a holder, during the same GetHitChance) leaves a note: PendingCalc = the
//             to-hit calc object of that shot, PendingAttacker / PendingTarget = its two units. The delegate acts only when the calc it receives IS the noted one,
//             and clears the notes. UT_Trait_Reliable.OnPostTemplatesCreated puts the delegate in FRONT of the array of every StandardAim calc (LWOTC's own
//             delegate, the graze band, comes after it and so reads the converted table; it returns true, ours returns false: the default or LWOTC finalization
//             then goes on). Several copies of the delegate on a shared calc are harmless (the note is cleared by the first).
//           - Reaction fire: normally it has no crit chance (the game removes it) and so converts nothing, but when an effect allows reaction crits (Guard, Cool
//             Under Pressure, Intercept...) the shot keeps its crit chance and is converted like any other (the delegate reads the final table, whatever the kind
//             of shot). An ability that guarantees the crit (Bullseye, Haymaker) is only denied the crit (see below).
//           - The delegate KNOWS whether the shot is a reaction shot: the calc object it receives is a StandardAim and StandardAim.bReactionFire is the very flag
//             the game tests to apply the reaction penalty (a property of the ability's calc, true for the reaction abilities, false for a normal shot).
//           - Order problem and its fix: GetHitChance does (1) every modifier incl. the crit ones, (2) for a reaction shot, the penalty
//             Success -= int(Success * GetReactionAdjust(shooter, target)) and the flat reaction bonuses (Guard...), (3) FinalizeHitChance = our delegate. So the aim
//             we add is added AFTER the reaction penalty and would not be reduced by it, unlike every other aim bonus of a reaction shot. Adding it BEFORE (between
//             (1) and (2)) is only possible from GetAdditionalHitModifiers_CH, a method of a SUBCLASS of the calc: it would mean replacing the calc of every ability
//             by a class of ours, which clashes with other mods' calcs (XMB...). So the gain is reduced here by the same rule instead: for a reaction shot (and not a
//             guaranteed hit, which the game does not penalize), AimGain -= int(AimGain * GetReactionAdjust(PendingAttacker, PendingTarget)); GetReactionAdjust is a
//             public function of the calc (it returns the FRACTION removed; 0 when the shooter went into overwatch concealed, a different value against a dashing
//             target), which is why the two units are noted. It is an approximation: the game would round int((S + A) * adjust) on the whole success chance S + A,
//             we round int(A * adjust) on our part alone, so the result can differ by 1 point.
//           - Indirect fire (grenades, rockets) and guaranteed hits already hit 100 %, so they get NO aim gain (it would change nothing real and only add a
//             pointless line / push FinalHitChance above 100). Their crit chance is still removed, e.g. the one Biggest Booms gives a grenade (an explosive can
//             crit through that perk, hence with Reliable its crit bonus and its crit damage are never used).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Reliable extends X2Effect_Persistent;

// The note left for the delegate by the holder's shot being computed. INSTANCE variables, on purpose: UnrealScript refuses to change at run time the default
// of a property that is not config, so a static delegate could not share them. The delegate below is
// therefore a method of this very effect object, which both GetToHitModifiers (called on the template's effect through EffectState.GetX2Effect()) and
// UT_Trait_Reliable.OnPostTemplatesCreated (which takes the effect from the 'UT_Reliable' template) reach: it is ONE object.
var transient X2AbilityToHitCalc PendingCalc;
var transient XComGameState_Unit PendingAttacker, PendingTarget;

function GetToHitModifiers(XComGameState_Effect EffectState, XComGameState_Unit Attacker, XComGameState_Unit Target, XComGameState_Ability AbilityState, class<X2AbilityToHitCalc> ToHitType, bool bMelee, bool bFlanking, bool bIndirectFire, out array<ShotModifierInfo> ShotModifiers)
{
	local X2AbilityTemplate AbilityTemplate;

	if (AbilityState == none)
		return;

	AbilityTemplate = AbilityState.GetMyTemplate();
	if (AbilityTemplate != none)
	{
		PendingCalc = AbilityTemplate.AbilityToHitCalc;
		PendingAttacker = Attacker;
		PendingTarget = Target;
	}
}

// Safety net: a critical result that is not removed from the table (an ability that guarantees the crit) becomes a hit.
function bool ChangeHitResultForAttacker(XComGameState_Unit Attacker, XComGameState_Unit TargetUnit, XComGameState_Ability AbilityState, const EAbilityHitResult CurrentResult, out EAbilityHitResult NewHitResult)
{
	if (CurrentResult == eHit_Crit)
	{
		NewHitResult = eHit_Success;
		return true;
	}

	return false;
}

// Puts the delegate below in FRONT of a calc's OverrideFinalHitChanceFns.
// A method of this object that names its own method as the delegate called by UT_Trait_Reliable.OnPostTemplatesCreated.
function RegisterDelegate(X2AbilityToHitCalc Calc)
{
	Calc.OverrideFinalHitChanceFns.InsertItem(0, OverrideFinalHitChance_Reliable);
}

// The delegate of OverrideFinalHitChanceFns. Always returns false: it only reshapes the table, the finalization (default or LWOTC's) goes on with it.
function bool OverrideFinalHitChance_Reliable(X2AbilityToHitCalc AbilityToHitCalc, out ShotBreakdown ShotBreakdown)
{
	local X2AbilityToHitCalc_StandardAim StandardAim;
	local XComGameState_Unit ShotAttacker, ShotTarget;
	local ShotModifierInfo ModInfo;
	local int Crit, Divisor, AimGain, DodgeCut;

	if (PendingCalc == none || PendingCalc != AbilityToHitCalc)
		return false;

	ShotAttacker = PendingAttacker;
	ShotTarget = PendingTarget;
	PendingCalc = none;
	PendingAttacker = none;
	PendingTarget = none;

	StandardAim = X2AbilityToHitCalc_StandardAim(AbilityToHitCalc);
	Crit = ShotBreakdown.ResultTable[eHit_Crit];
	if (StandardAim == none || Crit <= 0)
		return false;

	// The crit chance is removed for every kind of shot, reaction fire included when an effect lets it crit (Guard, Cool Under Pressure, Intercept...).
	ShotBreakdown.ResultTable[eHit_Crit] -= Crit;
	ModInfo.ModType = eHit_Crit;
	ModInfo.Value = -Crit;
	ModInfo.Reason = class'UT_Trait_Reliable'.default.ReliableReason;
	ShotBreakdown.Modifiers.AddItem(ModInfo);

	// An ability that guarantees the crit (bHitsAreCrits: Bullseye, Haymaker...) carries an ARTIFICIAL 100 crit chance, with no real crit sources behind it
	// (the game ignores the crit modifiers for it): nothing to convert. The slice is only removed, so the breakdown does not announce a crit that cannot
	// happen; the result is still rolled as a crit (HitsAreCrits) and turned into a plain hit by ChangeHitResultForAttacker. (LWOTC's finalization,
	// which runs after this delegate, may still display its own crit entry for such an ability.)
	if (StandardAim.bHitsAreCrits)
		return false;

	Divisor = Max(1, class'UT_Trait_Reliable'.default.RELIABLE_CRIT_TO_AIM_DIVISOR);
	AimGain = (Crit + Divisor - 1) / Divisor;
	DodgeCut = Min(Crit * class'UT_Trait_Reliable'.default.RELIABLE_DODGE_REDUCTION_PCT / 100, Max(0, ShotBreakdown.ResultTable[eHit_Graze]));

	// Indirect fire (grenades, rockets...) and guaranteed hits already hit 100 %: extra aim would change nothing real, only push FinalHitChance above 100 and add
	// a pointless line to the breakdown (Biggest Booms gives a grenade a real crit chance, which would otherwise be "converted" for nothing). The crit removal
	// above and the dodge cut stay.
	if (StandardAim.bIndirectFire || StandardAim.bGuaranteedHit)
		AimGain = 0;

	// A reaction shot: the game has already reduced the success chance by the reaction penalty (see the header), our gain gets the same reduction. A guaranteed
	// hit is not penalized by the game, so its gain stays whole (it is 0 above anyway).
	if (AimGain > 0 && StandardAim.bReactionFire && !StandardAim.bGuaranteedHit && ShotAttacker != none && ShotTarget != none)
		AimGain -= int(AimGain * StandardAim.GetReactionAdjust(ShotAttacker, ShotTarget));

	if (AimGain > 0)
	{
		ShotBreakdown.ResultTable[eHit_Success] += AimGain;
		ModInfo.ModType = eHit_Success;
		ModInfo.Value = AimGain;
		ShotBreakdown.Modifiers.AddItem(ModInfo);
	}

	if (DodgeCut > 0)
	{
		ShotBreakdown.ResultTable[eHit_Graze] -= DodgeCut;
		ModInfo.ModType = eHit_Graze;
		ModInfo.Value = -DodgeCut;
		ShotBreakdown.Modifiers.AddItem(ModInfo);
	}

	return false;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
