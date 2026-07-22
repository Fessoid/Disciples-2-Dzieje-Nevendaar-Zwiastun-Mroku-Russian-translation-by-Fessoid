--[[ Settings for Disciples 2 Rise of the Elves v3.01 mss32 proxy dll ]]--

settings = {
	-- Show troops banners
	showBanners = false,
	-- Show resources panel
	showResources = true,
	-- Show percentage of land coverted
	showLandConverted = false,

	-- Allow scenarios with prebuilt capital cities
	preserveCapitalBuildings = true,
        -- Start with pre built temple in capital for warrior lord
	buildTempleForWarriorLord = false,
	-- Maximum number of items the player is allowed to transfer
	-- between campaign scenarios [0 : INT_MAX]
	carryOverItemsMax = 6,

	-- Maximum unit damage per attack [300 : INT_MAX]
	unitMaxDamage = 500,
	-- Maximum combined unit armor [70 : INT_MAX]
	-- minimum value could not be less than highest armor value
	-- of all units in GUnits.dbf
	-- For example: not less than 65 because of Onyx Gargoyle in original game
	unitMaxArmor = 95,

	-- Maximum allowed scout range for troops [7 : 100]
	stackMaxScoutRange = 8,

	-- Total armor shatter damage [0 : 100]
	shatteredArmorMax = 100,
	-- Maximum armor shatter damage per attack [0 : 100]
	shatterDamageMax = 100,
	-- Percentage of damage upgrade value that shatter attack receives when a units levels up [0 : 255]
	shatterDamageUpgradeRatio = 100,
	-- Allow shatter attacks to miss
	allowShatterAttackToMiss = true,

	-- Percentage damage of critical hit [0 : 255]
	criticalHitDamage = 5,
	-- Percentage chance of critical hit [0 : 100]
	criticalHitChance = 100,

	-- Percentage of L_DRAIN attacks damage used as heal [INT_MIN : INT_MAX]
	drainAttackHeal = 50,
	-- Percentage of L_DRAIN_OVERFLOW attacks damage used as heal [INT_MIN : INT_MAX]
	drainOverflowHeal = 50,

	-- Change doppelganger attacks to copy units with respect to their level
	leveledDoppelgangerAttack = true,
	-- Change transform self attacks to compute transformed unit level using 'transformSelf.lua' script
	leveledTransformSelfAttack = true,
	-- Change transform other attacks to compute transformed unit level using 'transformOther.lua' script
	leveledTransformOtherAttack = false,
	-- Change drain level attacks to compute transformed unit level using 'drainLevel.lua' script
	leveledDrainLevelAttack = false,
	-- Change summon attacks to compute summoned units levels using 'summon.lua' script
	leveledSummonAttack = true,
	
	-- Change doppelganger attacks to respect enemy/ally wards and immunities to the attack class and source
	doppelgangerRespectsEnemyImmunity = true,
	doppelgangerRespectsAllyImmunity = true,

    -- Allows transform self attack to not consume a unit turn for transformation (once per turn)
	freeTransformSelfAttack = true,
	-- Allows free transform-self attack to be used infinite number of times per single turn
    freeTransformSelfAttackInfinite = true,
	
	-- Fix various bestow wards bugs and restrictions
	unrestrictedBestowWards = true,

	-- Round in battle after which paralyze and petrify attacks
	-- starts missing targets constantly [1 : INT_MAX]
	disableAllowedRoundMax = 40,
	
	-- Change accuracy reduction for mage leaders per each additional target
	mageLeaderAccuracyReduction = 10,

	aiAccuracyBonus = {
		-- Treat AI accuracy bonus as absolute value or as percentage.
		-- Absolute: accuracy += bonus;
		-- Percentage: accuracy += accuracy * bonus / 100;
		absolute = true,
		-- AI accuracy bonus on easy difficulty [-127 : 127]
		easy = -15,
		-- AI accuracy bonus on average difficulty [-127 : 127]
		average = 0,
		-- AI accuracy bonus on hard difficulty [-127 : 127]
		hard = 5,
		-- AI accuracy bonus on very hard difficulty [-127 : 127]
		veryHard = 10
	},

	movementCost = {
		-- Show stacks movement cost
		show = true,
		-- Color components are all in range [0 : 255]
		textColor = {
			red = 200, green = 200, blue = 200
		},
		outlineColor = {
			red = 0, green = 0, blue = 0
		}
	},
	
	-- Fix leader transformation (doppelganger, drain-level, transform-self/other attacks)
    -- to allow usage of battle items (potions, orbs and talismans)
    allowBattleItems = {
        -- If leader is transformed by TransformOther attack (Witch, orb/talisman, artifact effect, etc.)
        onTransformOther = true,
        -- If leader is transformed by TransformSelf attack (Wolf Lord, orb/talisman, artifact effect, etc.)
        onTransformSelf = true,
        -- If leader's level is drained by DrainLevel attack (Wight, orb/talisman, artifact effect, etc.)
        onDrainLevel = true,
        -- If leader transformed himself by Doppelganger attack
        onDoppelganger = true,
    },

	-- If true, switches attacks miss check to a single random value roll
	-- instead of check against arithmetic mean of two random numbers
	missChanceSingleRoll = false,
	
	-- Fix missing attack information in unit encyclopedia
	detailedAttackDescription = true,

	-- Create mss32 proxy dll log files with debug info
	debugHooks = true,
	
	unitEncyclopedia = {
		-- Additional display of some stats bonuses, regeneration, xp reward for killing, etc.
		detailedUnitDescription = true,
		
		-- Additional display of bonus hit points
		-- Requires detailedUnitDescription
		displayBonusHp = true,

		-- Additional display of experience points reduction
		-- Requires detailedUnitDescription
		displayBonusXp = true,
		
		-- Fix effective unit hp computation
	-- Original formula: (hp * armor / 100) + hp
	-- Fixed formula: hp / (1 - (armor / 100))
	fixEffectiveHpFormula = true,

		-- Additional display of some stats bonuses, drain, critical hit, custom attack ratios, etc.
		detailedAttackDescription = true,

		-- Additional display of dynamic upgrade values (only for unit type encyclopedia to avoid clutter)
		displayDynamicUpgradeValues = false,
		
		-- Display infinite effect indicator along with attack name (alternative to effect duration)
		-- Requires detailedUnitDescription
		displayInfiniteAttackIndicator = true,
	},
	
		-- Allows transformed leaders (doppelganger, drain-level, transform-self/other attacks) to use battle items (potions, orbs and talismans)
	allowBattleItems = {
		-- If leader is transformed by TransformOther attack (Witch, orb/talisman, artifact effect, etc.)
		onTransformOther = true,
		-- If leader is transformed by TransformSelf attack (Wolf Lord, orb/talisman, artifact effect, etc.)
		onTransformSelf = false,
		-- If leader's level is drained by DrainLevel attack (Wight, orb/talisman, artifact effect, etc.)
		onDrainLevel = false,
		-- If leader transformed himself by Doppelganger attack
		onDoppelganger = false,
	},

	modifiers = {
		-- Allow unit regeneration modifiers to stack.
		-- By default, the game picks single highest value, then sums it with lord, terrain and city bonuses.
		cumulativeUnitRegeneration = true,
		-- Enables 'onModifiersChanged' notification for custom modifier scripts.
		-- Keep it disabled if you don't need it to improve general performance.
		notifyModifiersChanged = false,
		-- Validate current HP / XP of units when their group changes (units added, removed, rearranged, etc.)
		-- to resolve issues with custom HP / XP modifiers, that depend on other units (like auras in MNS mod).
		-- Keep it disabled if you don't need it to improve general performance.
		validateUnitsOnGroupChanged = true,
	},

battle = {
  allowRetreatedUnitsToUpgrade = true,
  carryXpOverUpgrade = false,
  allowMultiUpgrade = false,
  debugAi = true,

  -- Nowa, elastyczna polityka fallbacku:
  fallbackAction = {
    mode = "context",  -- "fixed" | "weighted" | "context"

    -- używane gdy mode="fixed"
    fixed = BattleAction.Defend,

    -- używane gdy mode="weighted"
    weighted = {
      -- wagi (dowolne nieujemne liczby)
      { action = BattleAction.Attack, weight = 60 },
      { action = BattleAction.Defend, weight = 25 },
      { action = BattleAction.Wait,   weight = 10 },
      { action = BattleAction.Retreat,weight = 5  },
      -- { action = BattleAction.UseItem, weight = 5, itemFilter = "healing" },
    },

    -- używane gdy mode="context"
    context = {
      -- progi i preferencje
      lowHpThreshold = 0.25,   -- <25% HP -> defensywnie/ucieczka/leczenie
      midHpThreshold = 0.60,   -- <60% HP -> ostrożny atak/def
      preferFrontline = true,  -- front: preferuj atak/defend, back: czekaj/atak dystans
      allowRetreat = true,     -- pozwól AI wybrać Retreat jako fallback

      -- priorytety działań w zależności od sytuacji
      priorities = {
        whenNoTargets   = { BattleAction.Defend, BattleAction.Wait },
        whenLowHp       = { BattleAction.UseItem, BattleAction.Retreat, BattleAction.Defend },
        whenRangedUnit  = { BattleAction.Attack, BattleAction.Wait, BattleAction.Defend },
        whenMeleeUnit   = { BattleAction.Attack, BattleAction.Defend, BattleAction.Wait },
        default         = { BattleAction.Attack, BattleAction.Defend, BattleAction.Wait },
      },

      -- selektor celu (gdy wybierzemy Attack)
      targetSelector = "closest",   -- "closest" | "lowestHp" | "highestDmg" | "random"
      -- filtr przedmiotów (gdy UseItem)
      itemFilter = "healing",       -- "healing" | "buff" | "any"
    },
  },
}
}



