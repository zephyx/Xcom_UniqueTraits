//---------------------------------------------------------------------------------------
//  FILE:   XComGameState_Effect_UT_Suppression.uc
//  PURPOSE: Companion gamestate class for X2Effect_UT_Suppression (the Laser designator's mark and the Apothecary's toxin): remembers the effects the mark took off its target when it was
//           applied (Shadowstep, Squadsight...), EXACTLY as they were applied: the application data holds the ability that provided the effect, its source and the reference of the
//           effect template (ability template name + index in its effects). When the mark ends, X2Effect_UT_Suppression applies those very effects again from the data, so the target gets
//           back the effect of the ability it had, not a copy of ours. Part of the saved history: a save made while a mark is active gives the effects back when it ends, after the
//           reload as before it.
//---------------------------------------------------------------------------------------
class XComGameState_Effect_UT_Suppression extends XComGameState_Effect;

var array<EffectAppliedData> SuppressedEffects;

defaultproperties
{
	bTacticalTransient = true
}
