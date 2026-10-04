//---------------------------------------------------------------------------------------
//  FILE:   X2ItemSlot_UniqueTraits.uc
//  PURPOSE: Registers the custom CHItemSlot templates (Community Highlander issue #118) of the traits that need one:
//           Support's vest slot and Maniac explosive's extra grenade pockets. A CHItemSlotSet subclass cannot also be an
//           X2Ability, so only the registration lives here: each slot's definition, rules and config are in its trait
//           (UT_Trait_Support.CreateVestSlot, UT_Trait_ManiacExplosive.CreateExtraPocketsSlot).
//---------------------------------------------------------------------------------------
class X2ItemSlot_UniqueTraits extends CHItemSlotSet;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(class'UT_Trait_Support'.static.CreateVestSlot());
	Templates.AddItem(class'UT_Trait_ManiacExplosive'.static.CreateExtraPocketsSlot());

	return Templates;
}
