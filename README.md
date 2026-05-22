# Homuncu PI — Update Website

This is the official update and project website for [**Homuncu PI**](https://code.manhart.space/mmit-home-automation/homuncu-pi), your ghost in a PI for plug and play home automation.

It serves two purposes:

1. **Project website** — describes the project, features, and provides downloads
2. **Update endpoint** — serves version files and archives for the built-in `update_service.py`

---

## Structure

```
├── index.html                  # Landing page
├── style.css                   # Green, playful theme
├── script.js                   # Tab switching, live version fetch
├── VERSION                     # Latest version (update_service.py default)
├── build-archives.sh           # Build script for creating & uploading archives
├── .env.example                # Template for SCP upload configuration
├── .gitignore                  # Ignores .env (local credentials)
├── img/
│   ├── logo.jpg                # Homuncu PI logo (green ghost in a raspberry)
│   ├── logo-small.png
│   └── favicon.ico
├── dl/
│   ├── stable/                 # Stable release channel
│   │   ├── VERSION             # e.g. "1.0.0"
   # Dev release channel
│       ├── VERSION             # e.g. "1.1.0-dev-20260527101500"
```

---

## Development

All files are plain HTML, CSS and JavaScript — no build step, no framework.
Edit the files locally and reload the browser to see changes.

```bash
# Serve locally for development (Python 3)
python3 -m http.server 8000
# Open http://localhost:8000
```

---

## Build & Deploy

### 1. Configure upload target

Copy `.env.example` to `.env` and fill in your server details:

```bash
cp .env.example .env
```

```env
HOMUNCU_SERVER="user@yourserver"
HOMUNCU_REMOTE_DIR="/var/www/homuncu-website/dl"
# HOMUNCU_PI_DIR="/path/to/homuncu-pi"    # optional, defaults to ../homuncu-pi
```

> `.env` is ignored by git (see `.gitignore`).

### 2. Build & upload

Run the build script from the project root:

```bash
./build-archives.sh
```

This will:

1. Read the current version from `../homuncu-pi/VERSION`
2. Detect whether it is a **stable** (`x.y.z`) or **dev** (contains suffix) release
3. Build a `.tar.gz` archive via `git archive HEAD`
4. Generate a SHA256 checksum
5. Write `VERSION` file into the appropriate channel directory
6. Upload everything to the configured server via SCP

---

## How the update mechanism works

The `update_service.py` on each Raspberry Pi uses this site as its update source:

| Config value | Description |
|---|---|
| `type` | `stable` or `dev` — which channel to check |
| `autoupdate` | `"Off"`, `"System"`, `"Homuncu"`, or `"All"` |
| `repoUrl` | URL pointing to this site's `dl/` directory |

**Update flow:**

1. `update_service.py` fetches `{repoUrl}/{type}/VERSION` and compares it with the local `VERSION` file
2. If a newer version is found and `autoupdate` permits it:
   - constructs the archive URL from the version (`homuncu-pi-{version}.tar.gz`)
3. Downloads the archive, verifies integrity, and extracts it to the project root
4. Preserves `config.yaml` and `venv/` during extraction
5. Logs a recommendation to restart the service

### Example config.yaml

```yaml
update:
  active: True
  repoUrl: "https://homuncu-pi.manhart.space/dl"
  type: stable
  autoupdate: "Off"
```

---

## Nginx

An example Nginx configuration is provided in `nginx-example.conf`.
It includes SSL, gzip compression, caching headers, and correct MIME types for `.tar.gz` and `.sha256` files.
