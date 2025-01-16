# [TF2] Taunt-tastic
Inspired by FlaminSarge's [[TF2] Taunt 'em](https://github.com/FlaminSarge/tf_tauntem) plugin.

Allows for players to use in-game commands to use a taunt through either a menu or by specifying an index.

This plugin calls VScript from Sourcepawn in order to force players to taunt to avoid requiring memory hacks.

## Features

### Player Commands
- `sm_taunt` - If used without any arguments, a menu will be displayed with all taunts that your current class can use
- `sm_taunt <index>` - Players can specify a taunt's item definition index
- `sm_taunt <full/partial name>` - Players can specify a taunt's full name in quotes or a string which a particular taunt's name contains

### Admin Commands
- `sm_taunt <target> <index | full/partial name>` - Admins with access to the `tf_taunt_tastic` permission or the `ADMFLAG_CHEATS` flag may target players
- `sm_taunt_cache` - Parses `configs/tf_taunt_tastic.cfg` and updates the available taunts for each class if changes were made

### Convars
- `sm_taunt_allow_while_taunting (default 0)` - Whether players should be able to taunt while already in a taunt