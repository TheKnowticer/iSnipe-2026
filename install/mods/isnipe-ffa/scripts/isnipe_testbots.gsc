// Temporary stationary test clients. Set isnipe_testbots_per_team to 0 to disable.
init()
{
    level thread isnipeStartTestBots();
}

isnipeStartTestBots()
{
    wait 5;
    desired = getDvarInt("isnipe_testbots_per_team");
    if (desired <= 0) return;
    if (desired > 4) desired = 4;
    if (!level.teamBased)
    {
        existing = 0;
        foreach (player in level.players)
            if (isDefined(player) && player isTestClient()) existing++;
        desired = desired * 2;
        while (existing < desired)
        {
            bot = addTestClient();
            if (!isDefined(bot)) break;
            bot thread isnipeJoinTestBot("autoassign");
            existing++;
            wait 1;
        }
        return;
    }
    allies = 0;
    axis = 0;
    foreach (player in level.players)
    {
        if (!isDefined(player) || !player isTestClient()) continue;
        if (!isDefined(player.pers["team"])) continue;
        if (player.pers["team"] == "allies") allies++;
        if (player.pers["team"] == "axis") axis++;
    }
    for (i = 0; i < desired; i++)
    {
        if (allies < desired)
        {
            bot = addTestClient();
            if (isDefined(bot))
            {
                bot thread isnipeJoinTestBot("allies");
                allies++;
            }
            wait 1;
        }
        if (axis < desired)
        {
            bot = addTestClient();
            if (isDefined(bot))
            {
                bot thread isnipeJoinTestBot("axis");
                axis++;
            }
            wait 1;
        }
    }
}

isnipeJoinTestBot(team)
{
    self endon("disconnect");
    wait 1;
    self notify("menuresponse", game["menu_team"], team);
    wait 1;
    self notify("menuresponse", game["menu_changeclass"], "class0");
}
