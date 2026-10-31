@echo off
cd /d "%~dp0"
start "" iw4x.exe -dedicated +set fs_game mods/isnipe-sd +set sv_lanonly 0 +set dedicated 2 +set net_port 28960 +exec isnipe-public.cfg +exec isnipe-dev.cfg +set g_gametype sd +map mp_terminal
