# Build and validation notes

## Custom IW4x DLL

The included binary was built from IW4x r5292, upstream commit `5aa3b338534a32d4575651e5a1f13b8d94db2182`. On Windows, install Visual Studio 2022 C++ build tools and the Windows SDK, clone `https://github.com/iw4x/iw4x-client.git`, check out that commit with full history, and initialize its submodules. Apply `source/iw4x-r5292-isnipe.patch` to that checkout, then run the project's premake and Win32 Release build commands:

```
git submodule update --init --recursive
git apply PATH_TO_REPOSITORY/source/iw4x-r5292-isnipe.patch
tools\premake5.exe vs2022
msbuild build\iw4x.sln /m /p:Configuration=Release /p:Platform=Win32
```

The output is `build/bin/Win32/Release/iw4x.dll`. Preserve the full Git history for the generated revision. Build-tool and dependency revisions must match upstream's submodules. Do not automatically update over the custom DLL.

## Fastfile

`source/asset-build/mods/isnipe-accuracy-build/` contains the editable weapon, preview material and image definitions; `source/asset-build/zone_source/` contains its zone manifest. With a compatible IW4x zonebuilder and original game/IW4x assets installed, copy those folders into the matching game-root locations and run `iw4x.exe -zonebuilder -stdout +buildmod isnipe-accuracy-build`. The resulting fastfile was deployed as each mode's `mod.ff`. The source files may reference additional original or IW4x game assets, including assets from the COD4 weapon pack; these are not all standalone source assets in this repository. A clean-room fastfile rebuild has not been verified. Use the supplied fastfiles for installation.

`source/menus/` and `source/mapvote/` preserve the available menu/map-vote source. These are not a claim that every bundled third-party asset is fully reproducible from this repository.

## Validation recorded when packaged

The source installation ran all three modes with r5292, the bundled custom DLL, and the listed mod folders; local server queries and the LAN panel responded. The user previously reported that map changes, map previews, radar behavior and the killfeed worked during play. All three modes started with protocol 153 and the existing fastfiles. An isolated S&D test exercised bots, announcements, weapon-icon lookup and panel identity validation. A clean-machine install, public client connections, full multiplayer gameplay, all possible map downloads, and complete gameplay validation have not been performed for this update.
