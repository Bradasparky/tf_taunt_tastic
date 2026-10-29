# [TF2] Taunt-tastic
Inspired by FlaminSarge's [[TF2] Taunt 'em](https://github.com/FlaminSarge/tf_tauntem) plugin.

This plugin calls VScript from Sourcepawn in order to force players to taunt to avoid requiring memory hacks.

### Compile Dependency
- [stocksoup](https://github.com/nosoop/stocksoup) - nosoop

### Features
- Allows for players to use any taunt and taunt unusual in the game (Unusuals only work with the taunt command!)
- Automatically parses the item schema and tf_english.txt to grab the latest taunts, and saves them to `data/tf_taunt_tastic/taunt_data.txt`

### Player Commands
- `sm_taunt [tauntid|full/partial name]` - If used without any arguments, open the taunt menu. Optionally specify an index or name.
- `sm_taunts|sm_taunt_list` - List all taunts for your current class.

### Admin Commands
- `sm_forcetaunt <#userid|target> <tauntid|full/partial taunt name>` - Allows admins to force players to taunt.
- `sm_utaunt [unusualid|full/partial name]` - If used without any arguments, open the unusual menu.
- `sm_utaunts|sm_utaunt_list` - List all taunt unusuals.

### ConVars
- `sm_utaunts_enabled (default 0)` - Whether unusual taunts should be enabled (Admin only)
- `sm_taunt_allow_while_taunting (default 0)` - Whether players should be able to taunt while already in a taunt.
- `sm_taunt_while_taunting_cooldown (default 2)` - If the above is enabled, the cooldown between taunts.
