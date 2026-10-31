// Persistent, append-only player K/D journal. Bots never appear in rankings.
init()
{
    level.isnipeLeaderboardReady = false;
    level.isnipeLeaderboard = [];
    level.isnipeLeaderboardIds = [];
    loadJournal();
    level.isnipeLeaderboardReady = true;
    level thread listenForLeaderboard();
}

loadJournal()
{
    if (!fileExists("isnipe_leaderboard.log")) return;
    handle = openFile("isnipe_leaderboard.log", "read");
    if (handle < 0)
    {
        println("iSnipe leaderboard: could not open journal");
        return;
    }
    for (;;)
    {
        line = readStream();
        if (!isDefined(line)) break;
        fields = strTok(line, "|");
        if (fields.size != 3) continue;
        if (fields[0] != "K" && fields[0] != "D") continue;
        id = safeText(fields[1]);
        name = safeText(fields[2]);
        if (id == "") continue;
        applyEvent(id, name, fields[0]);
    }
    closeFile();
}

recordDeath(attacker)
{
    if (!isPlayer(self)) return;
    victimIsBot = self isTestClient();
    if (!victimIsBot) self journalEvent("D");
    if (!isDefined(attacker) || !isPlayer(attacker) || attacker == self) return;
    if (attacker isTestClient()) return;
    if (victimIsBot && !getDvarInt("isnipe_lb_count_bot_kills")) return;
    if (level.teamBased && isDefined(self.pers["team"]) && isDefined(attacker.pers["team"]) && self.pers["team"] == attacker.pers["team"]) return;
    attacker journalEvent("K");
}

journalEvent(kind)
{
    if (!isDefined(self.guid) || self.guid == "") return;
    id = safeText(self.guid + "");
    name = safeText(self.name);
    if (id == "") return;
    if (name == "") name = "Player";
    // One complete line per event; the journal lives under this mod's scriptdata.
    fileWrite("isnipe_leaderboard.log", kind + "|" + id + "|" + name + "\n", "append");
    applyEvent(id, name, kind);
}

applyEvent(id, name, kind)
{
    key = "p" + id;
    if (!isDefined(level.isnipeLeaderboard[key]))
    {
        row = spawnStruct();
        row.id = id;
        row.kills = 0;
        row.deaths = 0;
        level.isnipeLeaderboard[key] = row;
        level.isnipeLeaderboardIds[level.isnipeLeaderboardIds.size] = key;
    }
    row = level.isnipeLeaderboard[key];
    if (name != "") row.name = name;
    if (kind == "K") row.kills++;
    else row.deaths++;
}

safeText(value)
{
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.";
    out = "";
    for (i = 0; i < value.size && i < 48; i++)
    {
        ch = getSubStr(value, i, i + 1);
        if (isSubStr(allowed, ch)) out += ch;
    }
    return out;
}

listenForLeaderboard()
{
    for (;;)
    {
        level waittill("say", message, player);
        if (!isDefined(player) || !isPlayer(player) || player isTestClient()) continue;
        command = toLower(message);
        if (command != "!lb" && command != "!leaderboard" && command != "!top10") continue;
        player thread showLeaderboard();
    }
}

showLeaderboard()
{
    self endon("disconnect");
    if (isDefined(self.isnipeLbShowing) && self.isnipeLbShowing) return;
    self.isnipeLbShowing = true;
    top = [];
    for (i = 0; i < level.isnipeLeaderboardIds.size; i++)
    {
        row = level.isnipeLeaderboard[level.isnipeLeaderboardIds[i]];
        insert = top.size;
        for (j = 0; j < top.size; j++)
        {
            if (higherRank(row, top[j])) { insert = j; break; }
        }
        if (insert >= 10) continue;
        last = top.size;
        if (last > 9) last = 9;
        for (j = last; j > insert; j--) top[j] = top[j - 1];
        top[insert] = row;
    }
    self lbTell("^3Server K/D leaderboard ^7(kills / deaths)");
    if (!top.size) self lbTell("No recorded players yet.");
    // Two entries per line keeps all ten visible in the normal chat window.
    for (i = 0; i < top.size; i += 2)
    {
        line = formatRow(top[i], i + 1);
        if (i + 1 < top.size) line += "  |  " + formatRow(top[i + 1], i + 2);
        self lbTell(line);
        wait 0.2;
    }
    self.isnipeLbShowing = false;
}

formatRow(row, rank)
{
    deaths = row.deaths;
    if (deaths < 1) deaths = 1;
    ratio = int((row.kills * 100.0) / deaths) / 100.0;
    return "^3" + rank + ". ^7" + row.name + " ^3" + ratio + " ^7(" + row.kills + "/" + row.deaths + ")";
}

higherRank(a, b)
{
    aDeaths = a.deaths;
    bDeaths = b.deaths;
    if (aDeaths < 1) aDeaths = 1;
    if (bDeaths < 1) bDeaths = 1;
    aRatio = a.kills * 1.0 / aDeaths;
    bRatio = b.kills * 1.0 / bDeaths;
    if (aRatio != bRatio) return aRatio > bRatio;
    if (a.kills != b.kills) return a.kills > b.kills;
    return a.deaths < b.deaths;
}

lbTell(text)
{
    exec("tellraw " + self getEntityNumber() + " \"" + text + "\"");
}
