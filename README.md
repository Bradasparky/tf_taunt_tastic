# [TF2] Taunt-tastic
Inspired by FlaminSarge's [[TF2] Taunt 'em](https://github.com/FlaminSarge/tf_tauntem) plugin.

This plugin avoids memory hacks by calling VScript from Sourcepawn to force players to taunt.

### Compile Dependency
- [stocksoup](https://github.com/nosoop/stocksoup) - nosoop

### Features
- Allows for players to use any taunt and taunt unusual in the game (Unusuals only work with the taunt command and are Admin only!)
- Automatically parses the item schema and tf_english.txt to grab the latest taunts, and saves them to `data/tf_taunt_tastic/taunt_data.txt`

### Player Commands
- `sm_taunt [tauntid|full/partial name]` - If used without any arguments, opens the taunt menu. Optionally specify an index or name.
- `sm_taunts|sm_taunt_list` - List all taunts for your current class.

### Admin Commands
- `sm_forcetaunt <#userid|name> <tauntid|full/partial taunt name>` - Allows admins to force players to taunt.
- `sm_utaunt [unusualid|full/partial name]` - If used without any arguments, opens the unusual menu. Optionally specify an index or name.
- `sm_utaunts|sm_utaunt_list` - List all taunt unusuals.

### ConVars
- `sm_utaunts_enabled (default 0)` - Whether unusual taunts should be enabled.
- `sm_taunt_allow_while_taunting (default 0)` - Whether players should be able to taunt while already in a taunt.
- `sm_taunt_while_taunting_cooldown (default 2)` - If the above is enabled, the cooldown between taunts.
