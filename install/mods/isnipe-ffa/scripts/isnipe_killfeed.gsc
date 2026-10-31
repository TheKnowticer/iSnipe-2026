// Custom obituary-only feed. Other game notifications remain in window 0.
init()
{
    level.isnipeKillfeedReady = false;
    if (!getDvarInt("isnipe_killfeed_enabled")) return;
    level.isnipeKillfeedEntries = [];
    level.isnipeKillfeedNextId = 0;
    level.isnipeKillIcons = [];
    level.isnipeKillIcons["rifle"] = ISnipeWeaponKillIcon("isnipe_cheytac_mp");
    level.isnipeKillIcons["m40"] = ISnipeWeaponKillIcon("isnipe_m40a3_mp");
    ISnipeLogWeaponAccuracy("isnipe_cheytac_mp");
    level.isnipeKillIcons["pistol"] = ISnipeWeaponKillIcon("deserteagle_tactical_mp");
    level.isnipeKillIcons["throwing"] = ISnipeWeaponKillIcon("throwingknife_mp");
    icons = getArrayKeys(level.isnipeKillIcons);
    for (i = 0; i < icons.size; i++)
    {
        icon = level.isnipeKillIcons[icons[i]];
        if (icon != "") precacheShader(icon);
        println("iSnipe killfeed icon " + icons[i] + ": " + icon);
    }
    level thread onConnect();
    level.isnipeKillfeedReady = true;
}

onConnect()
{
    for (;;)
    {
        level waittill("connected", player);
        if (!isDefined(player) || !isPlayer(player) || player isTestClient()) continue;
        player thread setupFeed();
    }
}

setupFeed()
{
    self endon("disconnect");
    self.isnipeKillfeedHud = [];
    x = getDvarFloat("isnipe_killfeed_x");
    y = getDvarFloat("isnipe_killfeed_y");
    for (i = 0; i < 4; i++)
    {
        row = spawnStruct();
        row.attacker = self createFeedElement(x + 80, y + i * 16, "right");
        row.victim = self createFeedElement(x + 128, y + i * 16, "left");
        row.icon = newClientHudElem(self);
        row.icon.horzAlign = "left_adjustable";
        row.icon.vertAlign = "top_adjustable";
        row.icon.alignX = "center";
        row.icon.alignY = "top";
        row.icon.x = x + 104;
        row.icon.y = y + i * 16;
        row.icon.sort = 110;
        row.icon.hideWhenInMenu = true;
        row.icon.alpha = 0;
        self.isnipeKillfeedHud[i] = row;
    }
    self refreshFeed();
}

createFeedElement(x, y, align)
{
    hud = newClientHudElem(self);
    hud.horzAlign = "left_adjustable";
    hud.vertAlign = "top_adjustable";
    hud.alignX = align;
    hud.alignY = "top";
    hud.x = x;
    hud.y = y;
    hud.font = "default";
    hud.fontScale = 1.1;
    hud.sort = 110;
    hud.hideWhenInMenu = true;
    hud.alpha = 0;
    return hud;
}

recordKill(attacker, means, weapon)
{
    if (!isPlayer(self)) return;
    entry = spawnStruct();
    entry.victim = self.name;
    entry.attacker = "";
    entry.icon = "";
    if (!isDefined(attacker) || !isPlayer(attacker))
        entry.attacker = "World";
    else if (attacker == self)
        entry.attacker = "Suicide";
    else
    {
        entry.attacker = attacker.name;
        entry.icon = weaponIcon(means, weapon);
    }
    entry.id = level.isnipeKillfeedNextId;
    level.isnipeKillfeedNextId++;
    entries = [];
    entries[0] = entry;
    for (i = 0; i < level.isnipeKillfeedEntries.size && entries.size < 4; i++)
        entries[entries.size] = level.isnipeKillfeedEntries[i];
    level.isnipeKillfeedEntries = entries;
    refreshAll();
    level thread expireEntry(entry.id);
}

weaponIcon(means, weapon)
{
    if (isDefined(means) && (means == "MOD_MELEE" || means == "MOD_MELEE_BLOOD")) return level.isnipeKillIcons["throwing"];
    if (!isDefined(weapon)) return "";
    if (isSubStr(weapon, "throwingknife")) return level.isnipeKillIcons["throwing"];
    if (isSubStr(weapon, "cheytac")) return level.isnipeKillIcons["rifle"];
    if (isSubStr(weapon, "m40a3")) return level.isnipeKillIcons["m40"];
    if (isSubStr(weapon, "deserteagle")) return level.isnipeKillIcons["pistol"];
    return "";
}

expireEntry(id)
{
    duration = getDvarFloat("isnipe_killfeed_time");
    if (duration <= 0) duration = 5;
    wait duration;
    entries = [];
    for (i = 0; i < level.isnipeKillfeedEntries.size; i++)
        if (level.isnipeKillfeedEntries[i].id != id)
            entries[entries.size] = level.isnipeKillfeedEntries[i];
    level.isnipeKillfeedEntries = entries;
    refreshAll();
}

refreshAll()
{
    for (i = 0; i < level.players.size; i++)
    {
        player = level.players[i];
        if (isDefined(player) && isDefined(player.isnipeKillfeedHud)) player refreshFeed();
    }
}

refreshFeed()
{
    for (i = 0; i < self.isnipeKillfeedHud.size; i++)
    {
        row = self.isnipeKillfeedHud[i];
        if (i < level.isnipeKillfeedEntries.size)
        {
            entry = level.isnipeKillfeedEntries[i];
            row.attacker setText(entry.attacker);
            row.victim setText(entry.victim);
            row.attacker.alpha = 1;
            row.victim.alpha = 1;
            if (entry.icon != "")
            {
                row.icon setShader(entry.icon, 40, 12);
                row.icon.alpha = 1;
            }
            else row.icon.alpha = 0;
        }
        else
        {
            row.attacker.alpha = 0;
            row.victim.alpha = 0;
            row.icon.alpha = 0;
        }
    }
}
