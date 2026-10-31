from pathlib import Path
import hashlib, json, secrets

root = Path(__file__).resolve().parent
panel = root / 'iSnipe-Control'
panel.mkdir(exist_ok=True)
settings_path = panel / 'panel-settings.json'
credentials_path = panel / 'panel-password.txt'
rcon_path = root / 'userraw' / 'isnipe-panel-rcon.cfg'
if any(p.exists() for p in (settings_path, credentials_path, rcon_path)):
    raise SystemExit('Existing panel credentials or RCON config found; nothing was overwritten.')
rcon = secrets.token_hex(32)
password = secrets.token_urlsafe(18)
salt = secrets.token_bytes(16)
settings = {'username': 'admin', 'password_salt': salt.hex(),
            'password_hash': hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 310000).hex(),
            'rcon_password': rcon, 'listen_port': 8787}
rcon_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2) + '\n', encoding='utf-8')
rcon_path.write_text('set rcon_password "' + rcon + '"\nset rcon_timeout "100"\nRconWhitelistAdd 127.0.0.1\n', encoding='utf-8')
credentials_path.write_text('Username: admin\nPassword: ' + password + '\n', encoding='utf-8')
print('Setup complete. Open iSnipe-Control/panel-password.txt for your initial login.')
print('Keep panel-settings.json and isnipe-panel-rcon.cfg private.')
