@echo off
cd /d "%~dp0"
start "" iw4x.exe -dedicated -console +set fs_game mods/isnipe-tdm +set sv_lanonly 0 +set dedicated 2 +set net_port 28961 +exec isnipe-public.cfg +exec isnipe-dev.cfg +exec isnipe-tdm.cfg +set g_gametype war +map mp_terminal
