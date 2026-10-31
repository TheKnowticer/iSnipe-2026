#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
//DO DVARS
// ANTI FLASH

init()
{
	level.scoreInfo = [];
	level.xpScale = getDvarInt( "scr_xpscale" );

	level.rankTable = [];

	precacheShader("white");

	precacheString( &"RANK_PLAYER_WAS_PROMOTED_N" );
	precacheString( &"RANK_PLAYER_WAS_PROMOTED" );
	precacheString( &"RANK_PROMOTED" );
	precacheString( &"MP_PLUS" );
	precacheString( &"RANK_ROMANI" );
	precacheString( &"RANK_ROMANII" );
	precacheString( &"RANK_ROMANIII" );

	if ( level.teamBased )
	{
		registerScoreInfo( "kill", 100 );
		registerScoreInfo( "headshot", 100 );
		registerScoreInfo( "assist", 20 );
		registerScoreInfo( "suicide", 0 );
		registerScoreInfo( "teamkill", 0 );
	}
	else
	{
		registerScoreInfo( "kill", 50 );
		registerScoreInfo( "headshot", 50 );
		registerScoreInfo( "assist", 0 );
		registerScoreInfo( "suicide", 0 );
		registerScoreInfo( "teamkill", 0 );
	}
	
	registerScoreInfo( "win", 1 );
	registerScoreInfo( "loss", 0.5 );
	registerScoreInfo( "tie", 0.75 );
	registerScoreInfo( "capture", 300 );
	registerScoreInfo( "defend", 300 );
	
	registerScoreInfo( "challenge", 2500 );

	level.maxRank = int(tableLookup( "mp/rankTable.csv", 0, "maxrank", 1 ));
	level.maxPrestige = int(tableLookup( "mp/rankIconTable.csv", 0, "maxprestige", 1 ));
	
	pId = 0;
	rId = 0;
	for ( pId = 0; pId <= level.maxPrestige; pId++ )
	{
		for ( rId = 0; rId <= level.maxRank; rId++ )
			precacheShader( tableLookup( "mp/rankIconTable.csv", 0, rId, pId+1 ) );
	}

	rankId = 0;
	rankName = tableLookup( "mp/ranktable.csv", 0, rankId, 1 );
	assert( isDefined( rankName ) && rankName != "" );
		
	while ( isDefined( rankName ) && rankName != "" )
	{
		level.rankTable[rankId][1] = tableLookup( "mp/ranktable.csv", 0, rankId, 1 );
		level.rankTable[rankId][2] = tableLookup( "mp/ranktable.csv", 0, rankId, 2 );
		level.rankTable[rankId][3] = tableLookup( "mp/ranktable.csv", 0, rankId, 3 );
		level.rankTable[rankId][7] = tableLookup( "mp/ranktable.csv", 0, rankId, 7 );

		precacheString( tableLookupIString( "mp/ranktable.csv", 0, rankId, 16 ) );

		rankId++;
		rankName = tableLookup( "mp/ranktable.csv", 0, rankId, 1 );		
	}

	maps\mp\gametypes\_missions::buildChallegeInfo();

	level thread patientZeroWaiter();
	
	level thread onPlayerConnect();
	level thread serverHUD();
}

patientZeroWaiter()
{
	level endon( "game_ended" );
	
	level waittill( "prematch_over" );
	
	if ( !matchMakingGame() )
	{
		if ( getDvar( "mapname" ) == "mp_rust" && randomInt( 1000 ) == 999 )
			level.patientZeroName = level.players[0].name;
	}
	else
	{
		if ( getDvar( "scr_patientZero" ) != "" )
			level.patientZeroName = getDvar( "scr_patientZero" );
	}
}

isRegisteredEvent( type )
{
	if ( isDefined( level.scoreInfo[type] ) )
		return true;
	else
		return false;
}


registerScoreInfo( type, value )
{
	level.scoreInfo[type]["value"] = value;
}


getScoreInfoValue( type )
{
	overrideDvar = "scr_" + level.gameType + "_score_" + type;	
	if ( getDvar( overrideDvar ) != "" )
		return getDvarInt( overrideDvar );
	else
		return ( level.scoreInfo[type]["value"] );
}


getScoreInfoLabel( type )
{
	return ( level.scoreInfo[type]["label"] );
}


getRankInfoMinXP( rankId )
{
	return int(level.rankTable[rankId][2]);
}


getRankInfoXPAmt( rankId )
{
	return int(level.rankTable[rankId][3]);
}


getRankInfoMaxXp( rankId )
{
	return int(level.rankTable[rankId][7]);
}


getRankInfoFull( rankId )
{
	return tableLookupIString( "mp/ranktable.csv", 0, rankId, 16 );
}


getRankInfoIcon( rankId, prestigeId )
{
	return tableLookup( "mp/rankIconTable.csv", 0, rankId, prestigeId+1 );
}

getRankInfoLevel( rankId )
{
	return int( tableLookup( "mp/ranktable.csv", 0, rankId, 13 ) );
}


onPlayerConnect()
{
	for(;;)
	{
		level waittill( "connected", player );

		/#
		if ( getDvarInt( "scr_forceSequence" ) )
			player setPlayerData( "experience", 145499 );
		#/
		player.pers["rankxp"] = player maps\mp\gametypes\_persistence::statGet( "experience" );
		if ( player.pers["rankxp"] < 0 ) // paranoid defensive
			player.pers["rankxp"] = 0;
		
		rankId = player getRankForXp( player getRankXP() );
		player.pers[ "rank" ] = rankId;
		player.pers[ "participation" ] = 0;

		player.xpUpdateTotal = 0;
		player.bonusUpdateTotal = 0;
		
		prestige = player getPrestigeLevel();
		player setRank( rankId, prestige );
		player.pers["prestige"] = prestige;

		player.postGamePromotion = false;
		if ( !isDefined( player.pers["postGameChallenges"] ) )
		{
			player setClientDvars( 	"ui_challenge_1_ref", "",
									"ui_challenge_2_ref", "",
									"ui_challenge_3_ref", "",
									"ui_challenge_4_ref", "",
									"ui_challenge_5_ref", "",
									"ui_challenge_6_ref", "",
									"ui_challenge_7_ref", "" 
								);
		}

		player setClientDvar( 	"ui_promotion", 0 );
		
		if ( !isDefined( player.pers["summary"] ) )
		{
			player.pers["summary"] = [];
			player.pers["summary"]["xp"] = 0;
			player.pers["summary"]["score"] = 0;
			player.pers["summary"]["challenge"] = 0;
			player.pers["summary"]["match"] = 0;
			player.pers["summary"]["misc"] = 0;

			// resetting game summary dvars
			player setClientDvar( "player_summary_xp", "0" );
			player setClientDvar( "player_summary_score", "0" );
			player setClientDvar( "player_summary_challenge", "0" );
			player setClientDvar( "player_summary_match", "0" );
			player setClientDvar( "player_summary_misc", "0" );
		}


		// resetting summary vars
		
		player setClientDvar( "ui_opensummary", 0 );
		player setClientDvar( "cl_maxpackets", 100 );
		player setClientDvar( "snaps", 30 );
		player setClientDvar( "rate", 45000 );
		
		player maps\mp\gametypes\_missions::updateChallenges();
		player.explosiveKills[0] = 0;
		player.xpGains = [];
		
		player.hud_scorePopup = newClientHudElem( player );
		player.hud_scorePopup.horzAlign = "center";
		player.hud_scorePopup.vertAlign = "middle";
		player.hud_scorePopup.alignX = "center";
		player.hud_scorePopup.alignY = "middle";
 		player.hud_scorePopup.x = 0;
 		if ( level.splitScreen )
			player.hud_scorePopup.y = -40;
		else
			player.hud_scorePopup.y = -60;
		player.hud_scorePopup.font = "hudbig";
		player.hud_scorePopup.fontscale = 0.75;
		player.hud_scorePopup.archived = false;
		player.hud_scorePopup.color = (0.5,0.5,0.5);
		player.hud_scorePopup.sort = 10000;
		player.hud_scorePopup maps\mp\gametypes\_hud::fontPulseInit( 3.0 );
		
		player thread onPlayerSpawned();
		player thread isnipeClassMenuListener();
		player thread onJoinedTeam();
		player thread onJoinedSpectators();
		
	}
}


onJoinedTeam()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill( "joined_team" );
		
		self thread removeRankHUD();
	}
}


onJoinedSpectators()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill( "joined_spectators" );
		self thread removeRankHUD();
	}
}


onPlayerSpawned()
{
	self endon("disconnect");
	
	for(;;)
	{
		self waittill("spawned_player");
		
        self allowAds(true);
        self thread isnipeAntiHardscope();
        self thread isnipeCampRadar();
        self notify("isnipe_loadout_restart");
        self thread doDvars();
		//self setPerk("specialty_marathon");
		// Disabled: refill after firing conflicts with normal ammunition.
		
		//self maps\mp\perks\_perks::givePerk("specialty_marathon");
		//self setPerk("specialty_bulletaccuracy");
	
		self thread giveTK();
		
		//self thread restart();
	}
}

// Stock S&D permits a loadout change during the opening grace period.
// Reapply our selected loadout after the stock class handler finishes.
isnipeClassMenuListener()
{
    self endon("disconnect");
    for (;;)
    {
        self waittill("menuresponse", menu, response);
        if (menu != game["menu_changeclass"]) continue;
        wait 0.2;
        if (!isAlive(self) || !isDefined(level.inGracePeriod) || !level.inGracePeriod) continue;
        if (isDefined(self.hasDoneCombat) && self.hasDoneCombat) continue;
        self notify("isnipe_loadout_restart");
        self thread doDvars();
    }
}


roundUp( floatVal )
{
	if ( int( floatVal ) != floatVal )
		return int( floatVal+1 );
	else
		return int( floatVal );
}


giveRankXP( type, value )
{
	self endon("disconnect");
	
	lootType = "none";
	
	if ( !self rankingEnabled() )
		return;
	
	if ( level.teamBased && (!level.teamCount["allies"] || !level.teamCount["axis"]) )
		return;
	else if ( !level.teamBased && (level.teamCount["allies"] + level.teamCount["axis"] < 2) )
		return;

	if ( !isDefined( value ) )
		value = getScoreInfoValue( type );

	if ( !isDefined( self.xpGains[type] ) )
		self.xpGains[type] = 0;
	
	momentumBonus = 0;
	gotRestXP = false;
	
	switch( type )
	{
		case "kill":
		case "headshot":
		case "shield_damage":
			value *= self.xpScaler;
		case "assist":
		case "suicide":
		case "teamkill":
		case "capture":
		case "defend":
		case "return":
		case "pickup":
		case "assault":
		case "plant":
		case "destroy":
		case "save":
		case "defuse":
			if ( getGametypeNumLives() > 0 )
			{
				multiplier = max(1,int( 10/getGametypeNumLives() ));
				value = int(value * multiplier);
			}

			value = int( value * level.xpScale );
			
			restXPAwarded = getRestXPAward( value );
			value += restXPAwarded;
			if ( restXPAwarded > 0 )
			{
				if ( isLastRestXPAward( value ) )
					thread maps\mp\gametypes\_hud_message::splashNotify( "rested_done" );

				gotRestXP = true;
			}
			break;
	}
	
	if ( !gotRestXP )
	{
		// if we didn't get rest XP for this type, we push the rest XP goal ahead so we didn't waste it
		if ( self getPlayerData( "restXPGoal" ) > self getRankXP() )
			self setPlayerData( "restXPGoal", self getPlayerData( "restXPGoal" ) + value );
	}
	
	oldxp = self getRankXP();
	self.xpGains[type] += value;
	
	self incRankXP( value );

	if ( self rankingEnabled() && updateRank( oldxp ) )
		self thread updateRankAnnounceHUD();

	// Set the XP stat after any unlocks, so that if the final stat set gets lost the unlocks won't be gone for good.
	self syncXPStat();

	if ( !level.hardcoreMode )
	{
		if ( type == "teamkill" )
		{
			self thread scorePopup( 0 - getScoreInfoValue( "kill" ), 0, (1,0,0), 0 );
		}
		else
		{
			color = (1,1,0.5);
			if ( gotRestXP )
				color = (1,.65,0);
			self thread scorePopup( value, momentumBonus, color, 0 );
		}
	}

	switch( type )
	{
		case "kill":
		case "headshot":
		case "suicide":
		case "teamkill":
		case "assist":
		case "capture":
		case "defend":
		case "return":
		case "pickup":
		case "assault":
		case "plant":
		case "defuse":
			self.pers["summary"]["score"] += value;
			self.pers["summary"]["xp"] += value;
			break;

		case "win":
		case "loss":
		case "tie":
			self.pers["summary"]["match"] += value;
			self.pers["summary"]["xp"] += value;
			break;

		case "challenge":
			self.pers["summary"]["challenge"] += value;
			self.pers["summary"]["xp"] += value;
			break;
			
		default:
			self.pers["summary"]["misc"] += value;	//keeps track of ungrouped match xp reward
			self.pers["summary"]["match"] += value;
			self.pers["summary"]["xp"] += value;
			break;
	}
}

updateRank( oldxp )
{
	newRankId = self getRank();
	if ( newRankId == self.pers["rank"] )
		return false;

	oldRank = self.pers["rank"];
	rankId = self.pers["rank"];
	self.pers["rank"] = newRankId;

	//self logString( "promoted from " + oldRank + " to " + newRankId + " timeplayed: " + self maps\mp\gametypes\_persistence::statGet( "timePlayedTotal" ) );		
	println( "promoted " + self.name + " from rank " + oldRank + " to " + newRankId + ". Experience went from " + oldxp + " to " + self getRankXP() + "." );
	
	self setRank( newRankId );
	
	return true;
}


updateRankAnnounceHUD()
{
	self endon("disconnect");

	self notify("update_rank");
	self endon("update_rank");

	team = self.pers["team"];
	if ( !isdefined( team ) )
		return;	

	// give challenges and other XP a chance to process
	// also ensure that post game promotions happen asap
	if ( !levelFlag( "game_over" ) )
		level waittill_notify_or_timeout( "game_over", 0.25 );
	
	
	newRankName = self getRankInfoFull( self.pers["rank"] );	
	rank_char = level.rankTable[self.pers["rank"]][1];
	subRank = int(rank_char[rank_char.size-1]);
	
	thread maps\mp\gametypes\_hud_message::promotionSplashNotify();

	if ( subRank > 1 )
		return;
	
	for ( i = 0; i < level.players.size; i++ )
	{
		player = level.players[i];
		playerteam = player.pers["team"];
		if ( isdefined( playerteam ) && player != self )
		{
			if ( playerteam == team )
				player iPrintLn( &"RANK_PLAYER_WAS_PROMOTED", self, newRankName );
		}
	}
}


endGameUpdate()
{
	player = self;			
}


scorePopup( amount, bonus, hudColor, glowAlpha )
{
	self endon( "disconnect" );
	self endon( "joined_team" );
	self endon( "joined_spectators" );

	if ( amount == 0 )
		return;

	self notify( "scorePopup" );
	self endon( "scorePopup" );

	self.xpUpdateTotal += amount;
	self.bonusUpdateTotal += bonus;

	wait ( 0.05 );

	if ( self.xpUpdateTotal < 0 )
		self.hud_scorePopup.label = &"";
	else
		self.hud_scorePopup.label = &"MP_PLUS";

	self.hud_scorePopup.color = hudColor;
	self.hud_scorePopup.glowColor = hudColor;
	self.hud_scorePopup.glowAlpha = glowAlpha;

	self.hud_scorePopup setValue(self.xpUpdateTotal);
	self.hud_scorePopup.alpha = 0.85;
	self.hud_scorePopup thread maps\mp\gametypes\_hud::fontPulse( self );

	increment = max( int( self.bonusUpdateTotal / 20 ), 1 );
		
	if ( self.bonusUpdateTotal )
	{
		while ( self.bonusUpdateTotal > 0 )
		{
			self.xpUpdateTotal += min( self.bonusUpdateTotal, increment );
			self.bonusUpdateTotal -= min( self.bonusUpdateTotal, increment );
			
			self.hud_scorePopup setValue( self.xpUpdateTotal );
			
			wait ( 0.05 );
		}
	}	
	else
	{
		wait ( 1.0 );
	}

	self.hud_scorePopup fadeOverTime( 0.75 );
	self.hud_scorePopup.alpha = 0;
	
	self.xpUpdateTotal = 0;		
}

removeRankHUD()
{
	self.hud_scorePopup.alpha = 0;
}

getRank()
{	
	rankXp = self.pers["rankxp"];
	rankId = self.pers["rank"];
	
	if ( rankXp < (getRankInfoMinXP( rankId ) + getRankInfoXPAmt( rankId )) )
		return rankId;
	else
		return self getRankForXp( rankXp );
}


levelForExperience( experience )
{
	return getRankForXP( experience );
}


getRankForXp( xpVal )
{
	rankId = 0;
	rankName = level.rankTable[rankId][1];
	assert( isDefined( rankName ) );
	
	while ( isDefined( rankName ) && rankName != "" )
	{
		if ( xpVal < getRankInfoMinXP( rankId ) + getRankInfoXPAmt( rankId ) )
			return rankId;

		rankId++;
		if ( isDefined( level.rankTable[rankId] ) )
			rankName = level.rankTable[rankId][1];
		else
			rankName = undefined;
	}
	
	rankId--;
	return rankId;
}


getSPM()
{
	rankLevel = self getRank() + 1;
	return (3 + (rankLevel * 0.5))*10;
}

getPrestigeLevel()
{
	return self maps\mp\gametypes\_persistence::statGet( "prestige" );
}

getRankXP()
{
	return self.pers["rankxp"];
}

incRankXP( amount )
{
	if ( !self rankingEnabled() )
		return;

	if ( isDefined( self.isCheater ) )
		return;
	
	xp = self getRankXP();
	newXp = (xp + amount);
	
	if ( self.pers["rank"] == level.maxRank && newXp >= getRankInfoMaxXP( level.maxRank ) )
		newXp = getRankInfoMaxXP( level.maxRank );
	
	self.pers["rankxp"] = newXp;
}

getRestXPAward( baseXP )
{
	if ( !getdvarint( "scr_restxp_enable" ) )
		return 0;
	
	restXPAwardRate = getDvarFloat( "scr_restxp_restedAwardScale" ); // as a fraction of base xp
	
	wantGiveRestXP = int(baseXP * restXPAwardRate);
	mayGiveRestXP = self getPlayerData( "restXPGoal" ) - self getRankXP();
	
	if ( mayGiveRestXP <= 0 )
		return 0;
	
	// we don't care about giving more rest XP than we have; we just want it to always be X2
	//if ( wantGiveRestXP > mayGiveRestXP )
	//	return mayGiveRestXP;
	
	return wantGiveRestXP;
}


isLastRestXPAward( baseXP )
{
	if ( !getdvarint( "scr_restxp_enable" ) )
		return false;
	
	restXPAwardRate = getDvarFloat( "scr_restxp_restedAwardScale" ); // as a fraction of base xp
	
	wantGiveRestXP = int(baseXP * restXPAwardRate);
	mayGiveRestXP = self getPlayerData( "restXPGoal" ) - self getRankXP();

	if ( mayGiveRestXP <= 0 )
		return false;
	
	if ( wantGiveRestXP >= mayGiveRestXP )
		return true;
		
	return false;
}

syncXPStat()
{
	xp = self getRankXP();
	
	self maps\mp\gametypes\_persistence::statSet( "experience", xp );
}

//because you can change class during 15 beginning seconds, gotta remove them during that time 5*3.5=17.5.
doDvars()
{
    self endon("disconnect");
    self endon("death");
    self endon("joined_spectators");
    self endon("isnipe_loadout_restart");
    wait 0.1;

    // Replace the class guns; objective and killstreak items must remain intact.
    weapons = self getWeaponsListPrimaries();
    foreach (weapon in weapons)
    {
        if (!isSubStr(weapon, "bomb") && !isSubStr(weapon, "killstreak"))
            self takeWeapon(weapon);
    }
    rifle = "isnipe_cheytac_mp";
    if (isDefined(self.curClass) && self.curClass == "class1")
        rifle = "isnipe_m40a3_mp";
    self giveWeapon(rifle);
    self giveMaxAmmo(rifle);
    self switchToWeapon(rifle);

    self takeWeapon("flash_grenade_mp");
    self takeWeapon("concussion_grenade_mp");
    self takeWeapon("smoke_grenade_mp");
    self takeWeapon("frag_grenade_mp");
    self takeWeapon("semtex_mp");
    self takeWeapon("c4_mp");
    self takeWeapon("claymore_mp");

    self _clearPerks();
    perks = [];
    // One engine perk per slot: Sleight of Hand, Stopping Power, Steady Aim.
    perks[0] = "specialty_fastreload";
    perks[1] = "specialty_bulletdamage";
    perks[2] = "specialty_bulletaccuracy";
    foreach (perk in perks)
    {
        self maps\mp\perks\_perks::givePerk(perk);
        pro = tableLookup("mp/perktable.csv", 1, perk, 8);
        if (pro != "" && pro != "specialty_null")
            self maps\mp\perks\_perks::givePerk(pro);
    }

    self ISnipeGrantMarathon();

    pistol = "deserteagle_tactical_mp";
    if (!self hasWeapon(pistol))
        self giveWeapon(pistol);
    self setWeaponAmmoClip(pistol, 0);
    self setWeaponAmmoStock(pistol, 0);
    if (self isTestClient())
    {
        self BotWeapon(rifle);
    }
    speedTick = 0;
    for (;;)
    {
        wait 0.05;
        speedTick++;
        if (speedTick >= 5)
        {
            speedTick = 0;
            speed = getDvarFloat("isnipe_move_scale");
            if (speed < 0.5 || speed > 2) speed = 1.05;
            self setMoveSpeedScale(speed);
        }
        if (self hasWeapon(pistol))
        {
            self setWeaponAmmoClip(pistol, 0);
            self setWeaponAmmoStock(pistol, 0);
        }
    }
}

// Start timing as the weapon begins entering ADS.
isnipeAntiHardscope()
{
    self endon("disconnect");
    self endon("death");
    self endon("joined_spectators");
    limit = getDvarFloat("isnipe_ads_limit");
    if (limit < 0.05) limit = 0.5;
    adsTime = 0;
    for (;;)
    {
        wait 0.01;
        if (self playerAds() > 0)
            adsTime += 0.01;
        else
            adsTime = 0;
        if (adsTime >= limit)
        {
            self allowAds(false);
            while (self playerAds() > 0)
                wait 0.01;
            self allowAds(true);
            adsTime = 0;
        }
    }
}

// A stationary player's normal client compass marker is pulsed periodically.
isnipeCampRadar()
{
    self endon("disconnect");
    self endon("death");
    self endon("joined_spectators");
    threshold = getDvarFloat("isnipe_camp_time");
    radius = getDvarFloat("isnipe_camp_radius");
    interval = getDvarFloat("isnipe_camp_ping_interval");
    if (threshold < 1) threshold = 15;
    if (radius < 1) radius = 12;
    if (interval < 1) interval = 5;
    anchor = self.origin;
    nextPing = getTime() + int(threshold * 1000);
    for (;;)
    {
        wait 0.25;
        if (distance2d(self.origin, anchor) >= radius)
        {
            anchor = self.origin;
            nextPing = getTime() + int(threshold * 1000);
        }
        else if (getTime() >= nextPing)
        {
            self thread isnipeCompassPulse();
            nextPing = getTime() + int(interval * 1000);
        }
    }
}

isnipeCompassPulse()
{
    if (!getDvarInt("isnipe_camp_overlay"))
    {
        self ISnipeSetCompassPing(1, self getCurrentWeapon());
        return;
    }

    if (!isDefined(self.pers["team"])) return;
    campTeam = self.pers["team"];
    pingOrigin = self.origin;
    for (i = 0; i < level.players.size; i++)
    {
        viewer = level.players[i];
        if (!isDefined(viewer) || !isAlive(viewer) || !isDefined(viewer.pers["team"])) continue;
        if (viewer.pers["team"] == campTeam || viewer.pers["team"] == "spectator") continue;
        viewer thread isnipeRadarOverlayDot(pingOrigin);
    }
}

// A short-lived, last-known position drawn only for the opposing player.
// Coordinates are in the engine's 640x480 HUD space and are configurable.
isnipeRadarOverlayDot(pingOrigin)
{
    self endon("disconnect");
    mapX = getDvarFloat("isnipe_radar_x");
    mapY = getDvarFloat("isnipe_radar_y");
    mapSize = getDvarFloat("isnipe_radar_size");
    mapRange = getDvarFloat("isnipe_radar_range");
    duration = getDvarFloat("isnipe_radar_dot_time");
    if (mapSize <= 0) mapSize = 100;
    if (mapRange <= 0) mapRange = 2500;
    if (duration <= 0) duration = 1.5;

    dot = newClientHudElem(self);
    // Adjustable alignment follows the client's widescreen HUD safe area.
    dot.horzAlign = "left_adjustable";
    dot.vertAlign = "top_adjustable";
    dot.alignX = "center";
    dot.alignY = "middle";
    dot.sort = 100;
    dot setShader("compassping_enemyfiring", 12, 12);
    dot.alpha = 0;

    endTime = getTime() + int(duration * 1000);
    while (getTime() < endTime && isAlive(self))
    {
        delta = pingOrigin - self.origin;
        viewAngles = self getPlayerAngles();
        forward = anglesToForward((0, viewAngles[1], 0));
        // MW2's compass right axis points toward negative world Y at yaw 0.
        right = delta[0] * forward[1] - delta[1] * forward[0];
        ahead = delta[0] * forward[0] + delta[1] * forward[1];
        // The stock compass uses its full height / compassMaxRange.
        x = right * mapSize / mapRange;
        y = (0 - ahead) * mapSize / mapRange;
        // Clip along the ray from the centre so distant pings retain direction.
        // Leave half the icon width inside the minimap boundary.
        edge = mapSize / 2 - 6;
        if (edge < 1) edge = 1;
        extent = abs(x);
        if (abs(y) > extent) extent = abs(y);
        if (extent > edge)
        {
            x = x * edge / extent;
            y = y * edge / extent;
        }
        dot.x = mapX + x;
        dot.y = mapY + y;
        dot.alpha = 1;
        wait 0.05;
    }
    dot destroy();
}

GiveAmmo()
{
	for(;;)
	{
	self waittill("weapon_fired");
	weapon1=self getCurrentWeapon();
	self giveMaxAmmo(weapon1);
	
	}
}

serverHUD()
{
    info = level createServerFontString("objective", 0.85);
	info setPoint("TOPRIGHT", "TOPRIGHT", -8, 0);
	info.glowalpha = .5;
	info.glowcolor = ( 0, 1, 0 );
	info setText("iSnipe 2026");
	info.hideWhenInMenu = true;
}
giveTK()
{		
		
		self maps\mp\perks\_perks::givePerk("throwingknife_mp");
		self giveweapon("throwingknife_mp");
		
		
		

}







