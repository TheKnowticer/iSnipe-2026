# Created by fella_guy
# Contact at https://fella_guy.in or @fella_guy on Discord
# 
# Changelog
# v1 Supports usermaps and attempts to find the images for the usermaps as well.
# 
# v2 Added support for the COD4 and MW3 Map Packs that comes with IW4X


import os
import re
import zipfile
import shutil

# Directories
game_root = os.getcwd()
usermaps_dir = os.path.join(game_root, "usermaps")
vote_menu_path = os.path.join(game_root, "mods", "mapvote", "vote", "_vote_menu.gsc")
mod_file_path = os.path.join(game_root, "mods", "mapvote", "z_mapvote.iwd")
mod_images_dir = "images"  # Path inside the mod .iwd file for images
backup_file_path = os.path.join(game_root, "mods", "mapvote", "z_mapvote.backup")
zone_source_dir = os.path.join(game_root, "zone_source")
csv_f9_path = os.path.join(zone_source_dir, "f9.csv")
csv_f8_path = os.path.join(zone_source_dir, "f8.csv")
mods_f8_images = os.path.join(game_root, "mods", "f8", "images")
mods_f8_materials = os.path.join(game_root, "mods", "f8", "materials")
json_template_path = os.path.join(game_root, "mods", "previewName.iw4x.json")
iw4x_dir = os.path.join(game_root, "iw4x")  # DLC iwd location

# Ensure necessary directories exist
os.makedirs(mods_f8_images, exist_ok=True)
os.makedirs(mods_f8_materials, exist_ok=True)

# Define map packs (example entries)
cod4pack = [
    {
        "map_key": "downpour",
        "localised_name": "Downpour",
        "preview_name": "preview_mp_farm",
        "zone_name": "mp_farm",
    },
    {
        "map_key": "backlot",
        "localised_name": "Backlot",
        "preview_name": "preview_mp_backlot",
        "zone_name": "mp_backlot",
    },
    {
        "map_key": "pipeline",
        "localised_name": "Pipeline",
        "preview_name": "preview_mp_pipeline",
        "zone_name": "mp_pipeline",
    },
    {
        "map_key": "countdown",
        "localised_name": "Countdown",
        "preview_name": "preview_mp_countdown",
        "zone_name": "mp_countdown",
    },
    {
        "map_key": "crashsnow",
        "localised_name": "Winter Crash",
        "preview_name": "preview_mp_crash_snow",
        "zone_name": "mp_crash_snow",
    },
    {
        "map_key": "chinatown",
        "localised_name": "Chinatown",
        "preview_name": "preview_mp_carentan",
        "zone_name": "mp_carentan",
    },
    {
        "map_key": "broadcast",
        "localised_name": "Broadcast",
        "preview_name": "preview_mp_broadcast",
        "zone_name": "mp_broadcast",
    },
    {
        "map_key": "showdown",
        "localised_name": "Showdown",
        "preview_name": "preview_mp_showdown",
        "zone_name": "mp_showdown",
    },
    {
        "map_key": "ambush",
        "localised_name": "Ambush",
        "preview_name": "preview_mp_convoy",
        "zone_name": "mp_convoy",
    },
    {
        "map_key": "district",
        "localised_name": "District",
        "preview_name": "preview_mp_citystreets",
        "zone_name": "mp_citystreets",
    },
]


mw3pack = [
    {
        "map_key": "lockdown",
        "localised_name": "Lockdown",
        "preview_name": "preview_mp_alpha",
        "zone_name": "mp_alpha",
    },
    {
        "map_key": "mission",
        "localised_name": "Mission",
        "preview_name": "preview_mp_bravo",
        "zone_name": "mp_bravo",
    },
    {
        "map_key": "dome",
        "localised_name": "Dome",
        "preview_name": "preview_mp_dome",
        "zone_name": "mp_dome",
    },
    {
        "map_key": "hardhat",
        "localised_name": "Hardhat",
        "preview_name": "preview_mp_hardhat",
        "zone_name": "mp_hardhat",
    },
    {
        "map_key": "resistance",
        "localised_name": "Resistance",
        "preview_name": "preview_mp_paris",
        "zone_name": "mp_paris",
    },
    {
        "map_key": "arkaden",
        "localised_name": "Arkaden",
        "preview_name": "preview_mp_plaza2",
        "zone_name": "mp_plaza2",
    },
    {
        "map_key": "seatown",
        "localised_name": "Seatown",
        "preview_name": "preview_mp_seatown",
        "zone_name": "mp_seatown",
    },
    {
        "map_key": "underground",
        "localised_name": "Underground",
        "preview_name": "preview_mp_underground",
        "zone_name": "mp_underground",
    },
    {
        "map_key": "village",
        "localised_name": "Village",
        "preview_name": "preview_mp_village",
        "zone_name": "mp_village",
    },
]


# -------------------------------
# Process usermaps
# -------------------------------
def process_usermaps():
    map_data_lines = []
    preview_names = []

    # Delete existing z_mapvote.iwd
    if os.path.exists(mod_file_path):
        os.remove(mod_file_path)
        print(f"Deleted existing {mod_file_path}")

    # Make a copy of the backup .iwd file and rename it
    if os.path.exists(backup_file_path):
        shutil.copy(backup_file_path, mod_file_path)
        print(f"Restored {backup_file_path} to {mod_file_path}")
    else:
        print("Error: Backup file z_mapvote.backup not found.")
        return []

    # Process each map folder in the usermaps directory
    for map_folder in os.listdir(usermaps_dir):
        map_path = os.path.join(usermaps_dir, map_folder)
        if not os.path.isdir(map_path):
            continue

        arena_file = os.path.join(map_path, f"{map_folder}.arena")
        if not os.path.exists(arena_file):
            print(f"Missing .arena file for {map_folder}, skipping...")
            continue

        with open(arena_file, 'r') as arena:
            arena_data = arena.read()
            map_name = re.search(r'map\s+"(.+?)"', arena_data)
            localised_name = re.search(r'longname\s+"(.+?)"', arena_data)
            preview_name = re.search(r'mapimage\s+"(.+?)"', arena_data)

            if not map_name or not localised_name or not preview_name:
                print(f"Missing data in {map_folder}, skipping...")
                continue

            map_key = map_name.group(1)
            localised_name = localised_name.group(1)
            preview_name = preview_name.group(1)

            preview_names.append(preview_name)

            map_data_lines.append(f'\n\tlevel.iw4xmaps["{map_key}"] = [];\n')
            map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["localised_name"] = "{localised_name}";\n')
            map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["preview_name"] = "{preview_name}";\n')
            map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["zone_name"] = "{map_key}";\n')

            handle_iwi_file(map_path, map_folder, map_key, preview_name)

    update_csv(preview_names)
    return map_data_lines

# -------------------------------
# Process DLC packs
# -------------------------------
def process_pack(pack_list, pack_name):
    map_data_lines = []
    preview_names = []

    for m in pack_list:
        map_key = m["map_key"]
        localised_name = m["localised_name"]
        preview_name = m["preview_name"]
        zone_name = m["zone_name"]

        map_data_lines.append(f'\n\tlevel.iw4xmaps["{map_key}"] = [];\n')
        map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["localised_name"] = "{localised_name}";\n')
        map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["preview_name"] = "{preview_name}";\n')
        map_data_lines.append(f'\tlevel.iw4xmaps["{map_key}"]["zone_name"] = "{zone_name}";\n')

        preview_names.append(preview_name)

        # Search DLC iwds
        found = False
        for dlc_file in sorted(os.listdir(iw4x_dir)):
            if not dlc_file.startswith("iw") or not dlc_file.endswith(".iwd"):
                continue
            dlc_path = os.path.join(iw4x_dir, dlc_file)
            iwi_file = find_loadscreen_file(dlc_path, zone_name, True)
            if iwi_file:
                temp_iwi_path = os.path.join(game_root, "temp.iwi")
                with zipfile.ZipFile(dlc_path, 'r') as iwd:
                    with open(temp_iwi_path, 'wb') as iwi_output:
                        iwi_output.write(iwd.read(iwi_file))

                renamed_preview_name = f"{preview_name}.iwi"
                add_to_mod_iwd(temp_iwi_path, renamed_preview_name)

                dst_iwi_path = os.path.join(mods_f8_images, renamed_preview_name)
                if os.path.exists(dst_iwi_path):
                    os.remove(dst_iwi_path)
                shutil.copy(temp_iwi_path, dst_iwi_path)
                print(f"Copied {renamed_preview_name} from {dlc_file}")

                update_json_and_copy(preview_name)
                os.remove(temp_iwi_path)
                found = True
                break

        if not found:
            print(f"[{pack_name}] No loadscreen found for {map_key}")

    update_csv(preview_names)
    return map_data_lines

# -------------------------------
# CSV / JSON helpers
# -------------------------------
def init_csv():
    if os.path.exists(csv_f8_path):
        os.remove(csv_f8_path)
        print(f"Deleted {csv_f8_path}")

    if os.path.exists(csv_f9_path):
        shutil.copy(csv_f9_path, csv_f8_path)
        print(f"Copied {csv_f9_path} to {csv_f8_path}")
    else:
        print("Error: f9.csv not found.")
        return

def update_csv(preview_filenames):
    with open(csv_f8_path, 'a') as f8_csv:
        for preview_name in preview_filenames:
            f8_csv.write(f"material,{preview_name}\n")
    print(f"Updated {csv_f8_path}")

def update_json_and_copy(preview_name):
    dst_json_path = os.path.join(mods_f8_materials, f"{preview_name}.iw4x.json")
    if os.path.exists(dst_json_path):
        os.remove(dst_json_path)
        print(f"Deleted {dst_json_path}")
    if os.path.exists(json_template_path):
        with open(json_template_path, 'r') as json_file:
            json_content = json_file.read().replace("previewName", preview_name)
        with open(dst_json_path, 'w') as new_json_file:
            new_json_file.write(json_content)
        print(f"Created JSON {dst_json_path}")

# -------------------------------
# IWI helpers
# -------------------------------
def handle_iwi_file(map_path, map_folder, map_key, preview_name):
    iwd_file = os.path.join(map_path, f"{map_folder}.iwd")
    if not os.path.exists(iwd_file):
        print(f"Missing .iwd for {map_key}")
        return

    iwi_file = find_loadscreen_file(iwd_file, map_key)
    if not iwi_file:
        print(f"No loadscreen for {map_key}")
        return

    temp_iwi_path = os.path.join(game_root, "temp.iwi")
    with zipfile.ZipFile(iwd_file, 'r') as iwd:
        with open(temp_iwi_path, 'wb') as iwi_output:
            iwi_output.write(iwd.read(iwi_file))

    renamed_preview_name = f"{preview_name}.iwi"
    add_to_mod_iwd(temp_iwi_path, renamed_preview_name)

    dst_iwi_path = os.path.join(mods_f8_images, renamed_preview_name)
    if os.path.exists(dst_iwi_path):
        os.remove(dst_iwi_path)
    shutil.copy(temp_iwi_path, dst_iwi_path)

    update_json_and_copy(preview_name)
    os.remove(temp_iwi_path)

def find_loadscreen_file(iwd_path, map_key, specific=False):
    map_key_lower = map_key.lower()
    
    with zipfile.ZipFile(iwd_path, 'r') as iwd:
        image_files = [
            f for f in iwd.namelist() 
            if f.lower().startswith('images/') and f.lower().endswith('.iwi')
        ]
        
        # First, try loadscreen files
        if specific:
            loadscreen_files = [
                f for f in image_files 
                if "loadscreen" in f.lower() and map_key_lower in f.lower()
            ]
            if loadscreen_files:
                return loadscreen_files[0]
            
            screen_files = [
                f for f in image_files 
                if "screen" in f.lower() and map_key_lower in f.lower()
            ]
            if screen_files:
                return screen_files[0]
        else:
            loadscreen_files = [f for f in image_files if "loadscreen" in f.lower()]
            if loadscreen_files:
                return loadscreen_files[0]
            
            screen_files = [
                f for f in image_files if "screen" in f.lower() and "mp_" in f.lower()
            ]
            if screen_files:
                return screen_files[0]
                
    return None

def add_to_mod_iwd(src_path, dst_filename):
    with zipfile.ZipFile(mod_file_path, 'a') as mod_iwd:
        mod_iwd.write(src_path, os.path.join(mod_images_dir, dst_filename))

# -------------------------------
# GSC updater
# -------------------------------
def update_vote_menu(usermap_data, cod4_data, mw3_data):
    with open(vote_menu_path, 'r') as vote_menu:
        lines = vote_menu.readlines()

    def replace_between(marker_start, marker_end, new_lines):
        start_idx = next((i for i, line in enumerate(lines) if marker_start in line), None)
        end_idx = next((i for i, line in enumerate(lines) if marker_end in line), None)
        if start_idx is None or end_idx is None or start_idx >= end_idx:
            print(f"Error: Section {marker_start} not found")
            return lines
        return lines[:start_idx + 1] + new_lines + lines[end_idx:]

    lines = replace_between("//Call of Duty 4 Pack", "//End of Call of Duty 4 Pack", cod4_data)
    lines = replace_between("//Modern Warfare 3 Pack", "//End of Modern Warfare 3 Pack", mw3_data)
    lines = replace_between("//INSERT USERMAPS HERE", "//USERMAPS END HERE", usermap_data)

    with open(vote_menu_path, 'w') as vote_menu:
        vote_menu.writelines(lines)

# -------------------------------
# Main
# -------------------------------
if __name__ == "__main__":
    print("Processing usermaps and packs...")

    init_csv()

    usermap_data = process_usermaps()
    cod4_data = process_pack(cod4pack, "COD4")
    mw3_data = process_pack(mw3pack, "MW3")

    update_vote_menu(usermap_data, cod4_data, mw3_data)

    print("Done! All usermaps and packs processed.")
