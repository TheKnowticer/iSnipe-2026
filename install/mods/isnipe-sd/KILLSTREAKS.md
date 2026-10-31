# Server killstreaks

Every loadout uses the stock earned and manually activated UAV and Counter-UAV
rewards. Their kill thresholds are `isnipe_uav_kills` and
`isnipe_counter_uav_kills` in `userraw/isnipe-dev.cfg`, defaulting to 3 and 4.
The Counter-UAV threshold must be higher than the UAV threshold. Other selected
or inherited rewards are discarded when the player's loadout is applied.

The normal stock UAV and Counter-UAV scripts manage radar state and expiration.
The stock streak counter resets on death, and earned unused rewards use the
game's player-persistent queue across round loadouts. Stock team-change handling
clears that queue, including for a player moved to another team.

Search and Destroy uses `scr_sd_winlimit 5`, with no separate round limit.
