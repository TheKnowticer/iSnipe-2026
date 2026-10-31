@echo off
cd /d "%~dp0"
start "" iw4x.exe -dedicated -console +set fs_game mods/isnipe-ffa +set sv_lanonly 0 +set dedicated 2 +set net_port 28962 +exec isnipe-public.cfg +exec isnipe-dev.cfg +exec isnipe-ffa.cfg +set g_gametype dm +map mp_terminal
