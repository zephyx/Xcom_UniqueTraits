# Unique Traits

## Main Goal

Add diversity to your campaign by giving some of your soldiers a unique trait.

There are **42 traits** covering a wide range of gameplay elements, including stats, damage, cover actions, skill trees and skill points, bondmates, new tactical abilities, and more.

- **35 traits** are available without additional mod requirements.
- **7 traits** require specific mods to be available: 5 for LWOTC and 2 for Community Promotion Screen.

Each trait provides a thematic advantage along with a corresponding drawback.

Each trait can only be assigned to one soldier at a time, meaning a maximum of 42 soldiers can have a trait simultaneously.

When a soldier with a trait dies or is dismissed, their trait becomes available again.

---

## Some Examples

- **Athlete:** +3 Mobility, +15 Dodge, -5 Aim, -10 Critical Chance. => new version to update
- **Pacifist:** Gains a new ability, *Stay Covered*. This free action activates if the soldier inflicted no damage during the previous turn. Allies within 6 tiles gain +10 Defense and +5 Dodge until the next turn. The soldier loses all Overwatch abilities.
- **Acrobat:** Gains the Skirmisher Grapple ability. Suffers -10 Aim and -10 Critical Chance when attacking targets below their elevation.
- **Bribe:** Generates +20 Supplies per month for the haven they advise. Increases squad infiltration time when deployed. **[LWOTC only; disabled without LWOTC]**
- **Thief:** Picking up loot during the XCOM turn grants one bonus movement point, once per turn. Has a 20% chance to secretly keep the item, meaning you lose the corresponding reward.
- **Cyborg:** Can only equip basic PCS. Replaced PCS are retained. Upon mission victory, has a 30% chance to upgrade the equipped PCS by one tier.
- ...

---

## How It Works

By default, all rookies who rank up naturally (by completing a mission, getting kills, or completing a covert action) receive a random trait.

This system was designed for balance, as the mod is intended to be played with **ChooseMyClass**, which offers three class choices whenever a rookie ranks up.

You can adjust the difficulty by changing your setup:

- **Without ChooseMyClass:** Harder. Some traits may be poorly suited to certain classes, and the random assignment can lead to unfortunate combinations.
- **With ChooseMyClass:** In roughly half of your rank-ups, you should find a suitable class among the three choices. The other half may be more frustrating.
- **With the "Trait Given at Recruitment" option enabled:** Easier. You know each rookie's trait from the beginning and can train them in a suitable class at the GTS.

---

## Exceptions

Some soldiers do not naturally receive a trait:

- Faction Heroes: Skirmisher, Reaper, and Templar.
- Aliens and ADVENT units.
- Mission, Covert Action, and Black Market rewards.
- POI rewards.
- MECs: converting a soldier with a trait into a MEC removes their trait.

These exceptions are intentional for balancing and compatibility reasons.

---

## Console Commands

If you want to assign a trait to one of the exceptions, you can use the following console command on the soldier's Armory screen:

```
AddUniqueTrait TraitName
```

Replace `TraitName` with the name of the trait you want to assign.

If the soldier already has a trait, it will be replaced.

**Important:** This command bypasses the uniqueness rule, allowing you to assign the same trait to multiple soldiers.

To remove a trait from a soldier, use:

```
RemoveUniqueTrait
```

These commands should only be used when necessary. Don't cheat! :P

---

## Mod Companions

- **MCM (Mod Configuration Menu):** Use MCM instead of editing INI files. Otherwise, your changes may be overwritten when I update those files. With MCM, any options you have modified will retain your settings, while untouched options will follow my updates.
- **Class Highlander:** My other mod, which restricts each class to one soldier. With 40–50 classes, plus playable aliens, ADVENT, faction heroes, and MECs, every campaign can be different!

---

## MCM Configuration

As mentioned above, you should use the **MCM mod** to configure this mod.

You can use either the original MCM or my fork, which fixes the tooltip issue. I have added a lot of tooltips to explain the available options.

MCM provides two configuration pages.

### Basic Configuration

The basic page contains the following options:

#### Trait Given at Recruitment

When enabled (disabled by default), all rookies receive a trait upon recruitment instead of waiting for their first natural rank-up.

#### Trait Probabilities

You can configure trait probabilities in several ways:

- **Default probability:** Set the default probability for each trait. By default, 41 traits share the same probability, while one trait is five times rarer.
- **Individual probability:** Override the default probability for a specific trait to make it more or less common.

**Note:** Setting a trait's probability to `0` prevents soldiers from naturally acquiring that trait. You can still assign it manually using the console command.

#### Disable a Trait

You can completely disable an individual trait.

Disabling a trait does more than set its probability to zero:

- All code associated with that trait is disabled.
- The trait will no longer function on your soldiers.
- Any modified stats associated with the trait will remain.

**Use this option only if a trait is causing bugs or conflicts with another mod.**

### Advanced Configuration

The advanced page contains **more than 150 options** for fine-tuning trait effects and balancing the mod to suit your preferences.

---

## Why Beta?

This mod modifies many different gameplay systems, so the risk of conflicts with other mods or existing functionality is relatively high.

### Tested Environments

Most testing has been performed in a Ted Jam environment, including:

- LWOTC
- Ted Jam
- Numerous additional classes
- Requiem
- ChooseMyClass
- Class Highlander
- And other mods

I have also performed some tests in a basic WOTC environment using only:

- War of the Chosen
- X2CommunityHighlander
- MCM

I will keep **BETA** in the title for a while and remove it if no solvable bugs are reported.

### Compatibility and Bug Reports

I will have an easier time investigating and fixing bugs reported in basic WOTC or Ted Jam environments.

I have not tested this mod with class overhaul mods such as RPGO. I cannot guarantee that I will be able to resolve compatibility issues with them, but you are welcome to report any problems you encounter.

You can also contact me on the **LWOTC Discord**, where my username is `zephyx`.

### What to Do If a Trait Causes Problems

If a specific trait causes issues in your campaign, you have two options:

1. **Remove the trait from a soldier** using the console command:

   RemoveUniqueTrait

2. **Disable the trait in MCM:** Open the mod's configuration, disable the problematic trait, then exit and relaunch the game.