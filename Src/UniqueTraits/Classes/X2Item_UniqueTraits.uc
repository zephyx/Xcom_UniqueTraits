//---------------------------------------------------------------------------------------
//  FILE:   X2Item_UniqueTraits.uc
//  PURPOSE: Registers the custom item templates of the traits that need one (an X2Item subclass cannot also be an
//           X2Ability): Scout's free scanner, defined in UT_Trait_Scout.CreateScannerItem.
//---------------------------------------------------------------------------------------
class X2Item_UniqueTraits extends X2Item config(UniqueTraits);

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Items;

	Items.AddItem(class'UT_Trait_Scout'.static.CreateScannerItem());
	Items.AddItem(class'UT_Trait_Coroner'.static.CreateAutopsyItem());

	return Items;
}
