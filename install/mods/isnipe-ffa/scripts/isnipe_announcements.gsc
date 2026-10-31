// Per-server announcement timers persist across map restarts in ScriptStorage.
init()
{
    level thread onConnect();
    level thread runScheduler();
}

onConnect()
{
    for (;;)
    {
        level waittill("connected", player);
        if (!isDefined(player) || !isPlayer(player) || player isTestClient()) continue;
        player thread welcome();
    }
}

welcome()
{
    self endon("disconnect");
    if (isDefined(self.pers["isnipeWelcomeSent"]) && self.pers["isnipeWelcomeSent"]) return;
    delay = getDvarFloat("isnipe_welcome_delay");
    if (delay < 0) delay = 0;
    wait delay;
    if (!getDvarInt("isnipe_announcements_enabled")) return;
    for (i = 1; i <= 4; i++)
    {
        message = getDvar("isnipe_welcome_" + i);
        if (message != "")
        {
            self ISnipeAnnouncePlayer(message);
            wait 0.3;
        }
    }
    self.pers["isnipeWelcomeSent"] = true;
}

runScheduler()
{
    for (;;)
    {
        if (getDvarInt("isnipe_announcements_enabled"))
        {
            now = getSystemTime();
            localMinute = ISnipeLocalMinute();
            hasHumans = false;
            if (isDefined(level.players))
                foreach (player in level.players)
                    if (isDefined(player) && isPlayer(player) && !player isTestClient()) hasHumans = true;
            for (i = 1; i <= 5; i++)
            {
                interval = getDvarInt("isnipe_announce_interval_" + i);
                message = getDvar("isnipe_announce_message_" + i);
                nextKey = "isnipe_announcement_next_" + i;
                intervalKey = "isnipe_announcement_interval_" + i;
                if (interval > 0 && message != "")
                {
                    if (!storageHas(intervalKey) || int(storageGet(intervalKey)) != interval || !storageHas(nextKey))
                    {
                        storageSet(intervalKey, "" + interval);
                        storageSet(nextKey, "" + (now + interval));
                    }
                    if (now >= int(storageGet(nextKey)))
                    {
                        if (hasHumans) ISnipeAnnounceAll(message);
                        storageSet(nextKey, "" + (now + interval));
                    }
                }
                else
                {
                    if (storageHas(intervalKey)) storageRemove(intervalKey);
                    if (storageHas(nextKey)) storageRemove(nextKey);
                }

                when = getDvar("isnipe_daily_time_" + i);
                dailyMessage = getDvar("isnipe_daily_message_" + i);
                dailyKey = "isnipe_announcement_daily_" + i;
                if (when.size == 5 && dailyMessage != "" && localMinute.size == 16 && getSubStr(localMinute, 11, 16) == when)
                {
                    if (!storageHas(dailyKey) || storageGet(dailyKey) != localMinute)
                    {
                        if (hasHumans) ISnipeAnnounceAll(dailyMessage);
                        storageSet(dailyKey, localMinute);
                    }
                }
            }
        }
        wait 2;
    }
}
