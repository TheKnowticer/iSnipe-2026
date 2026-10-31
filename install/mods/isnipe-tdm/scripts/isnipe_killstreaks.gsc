// Use stock MW2 earned-reward and UAV activation logic with a fixed loadout.
init()
{
    level thread onConnect();
}

onConnect()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread onLoadout();
    }
}

onLoadout()
{
    self endon("disconnect");
    for (;;)
    {
        self waittill("giveLoadout");
        self applyFixedKillstreaks();
    }
}

applyFixedKillstreaks()
{
    if (!level.killstreakRewards) return;
    uavKills = getDvarInt("isnipe_uav_kills");
    counterKills = getDvarInt("isnipe_counter_uav_kills");
    if (uavKills < 1) uavKills = 3;
    if (counterKills <= uavKills) counterKills = uavKills + 1;
    nukeKills = getDvarInt("isnipe_nuke_kills");
    if (nukeKills <= counterKills) nukeKills = 25;
    if (nukeKills <= counterKills) nukeKills = counterKills + 1;

    // Insert in kill-count order: stock reward iteration depends on that order.
    self.killStreaks = [];
    self.killStreaks[uavKills] = "uav";
    self.killStreaks[counterKills] = "counter_uav";
    self.killStreaks[nukeKills] = "nuke";

    // Keep already earned radar rewards across loadouts, discard inherited
    // rewards from other classes, and rebind the stock activation item.
    kept = [];
    if (isDefined(self.pers["killstreaks"]))
        foreach (reward in self.pers["killstreaks"])
            if (isDefined(reward) && (reward.streakName == "uav" || reward.streakName == "counter_uav" || reward.streakName == "nuke"))
                kept[kept.size] = reward;
    self.pers["killstreaks"] = kept;
    if (isDefined(self.pers["lastEarnedStreak"]) && self.pers["lastEarnedStreak"] != "uav" && self.pers["lastEarnedStreak"] != "counter_uav" && self.pers["lastEarnedStreak"] != "nuke")
        self.pers["lastEarnedStreak"] = undefined;

    uavWeapon = maps\mp\killstreaks\_killstreaks::getKillstreakWeapon("uav");
    counterWeapon = maps\mp\killstreaks\_killstreaks::getKillstreakWeapon("counter_uav");
    nukeWeapon = maps\mp\killstreaks\_killstreaks::getKillstreakWeapon("nuke");
    foreach (item in self getWeaponsListItems())
        if (isSubStr(item, "killstreak") && item != uavWeapon && item != counterWeapon && item != nukeWeapon)
            self takeWeapon(item);
    if (kept.size)
        self maps\mp\killstreaks\_killstreaks::giveOwnedKillstreakItem(true);
}
