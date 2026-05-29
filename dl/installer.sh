#!/usr/bin/env bash
set -euo pipefail

VERSION=1.0.0-dev
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error(){ echo -e "${RED}[✗]${NC} $*"; }
header(){ echo -e "\n${BOLD}${BLUE}── $* ──${NC}\n"; }

declare -A _A

ask() {
    local prompt="$1" default="$2" var="$3" input
    if [ -n "${_A[$var]:-}" ]; then
        printf -v "$var" "%s" "${_A[$var]}"
        log "$prompt: ${_A[$var]}"
        return
    fi
    local dsp="${default:+ ($default)}"
    read -r -p "$(echo -e "${CYAN}?>${NC} ${prompt}${dsp}: ")" input </dev/tty || true
    printf -v "$var" "%s" "${input:-$default}"
}

confirm() {
    local prompt="$1" default="${2:-n}" varname="${3:-}" answer
    if [ -n "$varname" ] && [ -n "${_A[$varname]:-}" ]; then
        answer=$(echo "${_A[$varname]}" | tr '[:upper:]' '[:lower:]')
        log "$prompt: $answer"
        [ "$answer" = "y" ] || [ "$answer" = "yes" ] || [ "$answer" = "true" ] || [ "$answer" = "1" ]
        return $?
    fi
    local dsp
    if [ "$default" = "y" ]; then dsp="Y/n"; else dsp="y/N"; fi
    read -r -p "$(echo -e "${CYAN}?>${NC} ${prompt} [${dsp}]: ")" answer </dev/tty || true
    answer=$(echo "${answer:-$default}" | tr '[:upper:]' '[:lower:]')
    [ "$answer" = "y" ] || [ "$answer" = "yes" ]
}

load_answers_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        error "Antwortdatei nicht gefunden: $file"
        exit 1
    fi
    log "Lade Antworten aus: $file"
    while IFS='=' read -r key value; do
        key="${key#"${key%%[![:space:]]*}"}"
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value#\"}"; value="${value%\"}"
        _A["$key"]="$value"
    done < "$file"
}

cleanup() { [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR" 2>/dev/null; }
trap cleanup EXIT

UPDATE_MODE=false
CONFIG_ONLY=false
LOCAL_VERSION=""
CONFIG_CHOICE="keep"
CONFIG_FILE=""

DOWNLOADER=""
detect_downloader() {
    if command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    elif command -v curl &>/dev/null; then
        DOWNLOADER="curl"
    else
        error "wget oder curl wird benötigt."
        exit 1
    fi
}

http_get() {
    local url="$1" out="$2"
    case "$DOWNLOADER" in
        wget) wget -q "$url" -O "$out" --show-progress 2>&1 || return 1;;
        curl) curl -sL "$url" -o "$out" --progress-bar 2>&1 || return 1;;
    esac
}

http_get_silent() {
    local url="$1" out="$2"
    case "$DOWNLOADER" in
        wget) wget -q "$url" -O "$out" 2>/dev/null || return 1;;
        curl) curl -sL "$url" -o "$out" 2>/dev/null || return 1;;
    esac
}

print_logo() {
    echo -e "${CYAN}"
    cat <<'LOGO'
                  % &## ## ## #                    %&#####&##& %
             #######((((((((((((((#(          ((((((((((((((((#######
            ###((((((((((((((((((((((/      /((((((((((((((((((((((###
             ((((((((((    &(((((((((//    (/(((((((((     (((((((((
             &((((((((((((((&    /((//(    ((///(    #(((((((((((((
               (((((((((((((//((     %      /    #///(((((((((((((
                 ((((((//////////(/            ///////////(((((((
                   /(////////////(              /////////////(#
                  &&&&#(////((      &#******%      #//////(&&&&&
                &&&&%%%%%&       &**&&&&&&&&&%**        ##%%%&&&&
               &&%%#(          &**&           &&*(          (#%%&&&
             &&%#(            &*(&             &&*%            (#%&&
            &&#&              /*&&   /-    -\   &/*&             &#%&
           &#&               &*%&     *    *    &&*/&              &#&
          ##  &&            (*%&                 &&**&           &&  ##
         #%  &&&         &#*#&&                   &&&/*&&         &%  ##
        ## &%%&&      &(*/%&&&                      &&&&***&      &&%& #%
       ##  %%%      &*(%&&&&&       (*\    /*)       &&&&%%*&      &%%  ##
        ## %%        &&/*(&&&&       \******/       &&&&**&&        %% ##&
        %#             &(**/&&&&                &&&&%%/*%              ##
         &#                &(*#&&&&&&         &&&%*(&&&               ##
          (#  &&            &(**/**%&&&&  &&&&&%**&               &  ((
           #(  &&                 &/*%&&&&&&&%/*%&              &&  ##
            &##  %&&               &*/%&&&%/*#&&             &&%& &#%
              %#(  &%&&&&            &*****/&           &&&&%%  (##
                &%(##    &&&                         &&&&   #((%&
                  &&&%#(((                             (#(#&&&&
                     &&&%%#(   &&               &&   (#%%&&&
                         &&%##   &%&&&&&&&&&&&%&   ##%&&
                              %###&    &&      ###%
                                   ###########&
LOGO
    echo -e "${NC}"
}

welcome() {
    echo -e "${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        Homuncu-Pi Installation Wizard v${VERSION}         ║" # a version number is 5 chars long, the variable 10 chars
    echo "║   Your Ghost in a PI - Home Automation Middleware    ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

get_base_url() {
    local default_url="https://homuncu.manhart.space/dl"
    if [ -n "${_A[BASE_URL]:-}" ]; then
        BASE_URL="${_A[BASE_URL]}"
        log "Basis-URL: $BASE_URL"
    elif [ -n "${HOMUNCU_BASE_URL:-}" ]; then
        BASE_URL="$HOMUNCU_BASE_URL"
        log "Basis-URL aus Umgebungsvariable: $BASE_URL"
    else
        ask "Download-Basis-URL" "$default_url" BASE_URL
    fi
    BASE_URL="${BASE_URL%/}"
}

get_channel() {
    if [ -n "${_A[CHANNEL]:-}" ]; then
        CHANNEL="${_A[CHANNEL]}"
        log "Channel: $CHANNEL"
        return
    fi
    echo -e "\n${BOLD}Welche Version möchtest du installieren?${NC}"
    echo "  ${BOLD}1${NC}) stable  - Empfohlen für den Produktiveinsatz"
    echo "  ${BOLD}2${NC}) dev     - Neueste Entwicklungen (experimentell)"
    local choice
    read -r -p "$(echo -e "${CYAN}?>${NC} Auswahl [1/2]: ")" choice </dev/tty || true
    case "$choice" in
        2|dev) CHANNEL="dev"; log "Dev-Channel ausgewählt" ;;
        *)     CHANNEL="stable"; log "Stable-Channel ausgewählt" ;;
    esac
}

fetch_version() {
    header "Aktuellste Version wird ermittelt"
    local version_url="$BASE_URL/$CHANNEL/VERSION"
    if ! http_get_silent "$version_url" "$TMPDIR/VERSION"; then
        error "Konnte VERSION nicht von $version_url laden."
        error "Bitte überprüfe die Basis-URL."
        exit 1
    fi
    REMOTE_VERSION=$(cat "$TMPDIR/VERSION" | tr -d '[:space:]')
    log "Entfernte Version: ${BOLD}$REMOTE_VERSION${NC}"
}

download_archive() {
    header "Archiv wird heruntergeladen"

    log "downloading the lastest $CHANNEL version: $REMOTE_VERSION"
    ARCHIVE_NAME="homuncu-pi-${REMOTE_VERSION}.tar.gz"

    local archive_url="$BASE_URL/$CHANNEL/$ARCHIVE_NAME"
    echo -e "${YELLOW}Lade $ARCHIVE_NAME herunter ...${NC}"
    if ! http_get "$archive_url" "$TMPDIR/$ARCHIVE_NAME"; then
        error "Download fehlgeschlagen: $archive_url"
        exit 1
    fi
    log "Download abgeschlossen ($(du -h "$TMPDIR/$ARCHIVE_NAME" | cut -f1))"

    local sha_url="$archive_url.sha256"
    if http_get_silent "$sha_url" "$TMPDIR/$ARCHIVE_NAME.sha256"; then
        log "SHA256-Prüfsumme geladen"
        local expected=$(cut -d' ' -f1 < "$TMPDIR/$ARCHIVE_NAME.sha256")
        local actual=$(sha256sum "$TMPDIR/$ARCHIVE_NAME" | cut -d' ' -f1)
        if [ "$expected" = "$actual" ]; then
            log "SHA256-Prüfsumme stimmt überein ${GREEN}✓${NC}"
        else
            error "SHA256-Prüfsumme stimmt NICHT überein!"
            error "Erwartet: $expected"
            error "Tatsächlich: $actual"
            exit 1
        fi
    else
        warn "Keine SHA256-Prüfsumme verfügbar, Überspringe Prüfung."
    fi
}

get_install_dir() {
    local default_dir="$HOME/homuncu-pi"
    if [ -n "${_A[INSTALL_DIR]:-}" ]; then
        INSTALL_DIR="${_A[INSTALL_DIR]}"
        log "Installationsverzeichnis: $INSTALL_DIR"
    elif [ -n "${HOMUNCU_INSTALL_DIR:-}" ]; then
        INSTALL_DIR="$HOMUNCU_INSTALL_DIR"
        log "Installationsverzeichnis aus Umgebungsvariable: $INSTALL_DIR"
    else
        ask "Installationsverzeichnis" "$default_dir" INSTALL_DIR
    fi
    INSTALL_DIR="${INSTALL_DIR%/}"
    CONFIG_FILE="$INSTALL_DIR/config.yaml"
}

check_existing_installation() {
    if [ ! -f "$INSTALL_DIR/VERSION" ]; then
        return
    fi

    UPDATE_MODE=true
    LOCAL_VERSION=$(cat "$INSTALL_DIR/VERSION" | tr -d '[:space:]')

    echo ""
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║        Bestehende Installation gefunden              ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo -e "  Installierte Version: ${BOLD}$LOCAL_VERSION${NC}"
    echo ""

    if [ -n "${_A[ACTION]:-}" ]; then
        case "${_A[ACTION]}" in
            config)
                CONFIG_ONLY=true
                log "Aktion: Nur Config-Anpassung"
                CONFIG_CHOICE="${_A[CONFIG_CHOICE]:-rewrite}"
                log "Config: ${_A[CONFIG_CHOICE]:-rewrite}"
                if [ "$CONFIG_CHOICE" = "keep" ]; then
                    log "Config-Anpassung abgebrochen (keep)."
                    exit 0
                fi
                return
                ;;
            *)
                CONFIG_ONLY=false
                log "Aktion: Vollständiges Update"
                CONFIG_CHOICE="${_A[CONFIG_CHOICE]:-keep}"
                log "Config: ${_A[CONFIG_CHOICE]:-keep}"
                return
                ;;
        esac
    fi

    echo -e "\n${BOLD}${BLUE}┌─ Aktionsauswahl ─────────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}Was möchtest du tun?${NC}"
    echo -e "  ${BOLD}1${NC}) Vollständiges Update (Programm + Config)"
    echo -e "  ${BOLD}2${NC}) Nur Config anpassen"
    local action_choice
    read -r -p "$(echo -e "${CYAN}?>${NC} Auswahl [1/2]: ")" action_choice </dev/tty || true
    case "$action_choice" in
        2)
            CONFIG_ONLY=true
            log "Nur Config-Anpassung."
            echo -e "\n${BOLD}${BLUE}┌─ Konfigurations-Upgrade ─────────────────────────────┐${NC}"
            echo -e "  ${YELLOW}Möchtest du die Konfiguration neu erstellen?${NC}"
            echo -e "  ${BOLD}1${NC}) Config-Wizard neu durchlaufen"
            echo -e "  ${BOLD}2${NC}) Abbrechen (nichts ändern)"
            local cfg_choice
            read -r -p "$(echo -e "${CYAN}?>${NC} Auswahl [1/2]: ")" cfg_choice </dev/tty || true
            case "$cfg_choice" in
                1)
                    CONFIG_CHOICE="rewrite"
                    log "Config wird neu erstellt."
                    ;;
                *)
                    log "Config-Anpassung abgebrochen."
                    exit 0
                    ;;
            esac
            ;;
        *)
            CONFIG_ONLY=false
            log "Vollständiges Update."

            echo -e "\n${BOLD}${BLUE}┌─ Konfigurations-Upgrade ─────────────────────────────┐${NC}"
            echo -e "  ${YELLOW}Wie möchtest du mit der bestehenden Konfiguration verfahren?${NC}"
            echo -e "  ${BOLD}1${NC}) Bestehende Konfiguration behalten"
            echo -e "  ${BOLD}2${NC}) Neue Konfiguration erstellen (Wizard neu durchlaufen)"
            echo -e "  ${BOLD}3${NC}) Nur neue Optionen abfragen ${YELLOW}(noch nicht implementiert)${NC}"
            local choice
            read -r -p "$(echo -e "${CYAN}?>${NC} Auswahl [1/2/3]: ")" choice </dev/tty || true
            case "$choice" in
                2)
                    CONFIG_CHOICE="rewrite"
                    log "Konfiguration wird neu erstellt."
                    ;;
                *)
                    CONFIG_CHOICE="keep"
                    log "Bestehende Konfiguration wird behalten."
                    ;;
            esac
            ;;
    esac
}

extract_archive() {
    header "Archiv wird extrahiert"

    if [ "$UPDATE_MODE" = true ]; then
        log "Update-Modus: Bestehende Installation wird aktualisiert"
        if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$TMPDIR/config.yaml.bak"
            log "Bestehende config.yaml gesichert"
        fi
        find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        log "Altes Verzeichnis geleert."
    else
        if [ -d "$INSTALL_DIR" ]; then
            if confirm "'$INSTALL_DIR' existiert bereits. Überschreiben?" "n" OVERWRITE; then
                find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                log "Altes Verzeichnis geleert."
            else
                warn "Installation abgebrochen."
                exit 1
            fi
        fi
    fi

    mkdir -p "$INSTALL_DIR"
    tar -xzf "$TMPDIR/$ARCHIVE_NAME" -C "$INSTALL_DIR"
    if [ -d "$INSTALL_DIR/homuncu-pi" ]; then
        shopt -s dotglob
        for f in "$INSTALL_DIR/homuncu-pi"/*; do
            mv "$f" "$INSTALL_DIR/"
        done
        rmdir "$INSTALL_DIR/homuncu-pi"
        shopt -u dotglob
    fi
    log "Archiv extrahiert nach: ${BOLD}$INSTALL_DIR${NC}"

    if [ "$UPDATE_MODE" = true ] && [ -f "$TMPDIR/config.yaml.bak" ]; then
        if [ "$CONFIG_CHOICE" = "keep" ]; then
            mv "$TMPDIR/config.yaml.bak" "$INSTALL_DIR/config.yaml"
            log "Bestehende config.yaml wiederhergestellt"
        else
            rm "$TMPDIR/config.yaml.bak"
        fi
    fi

    echo -e "  ${BLUE}Dateien:${NC} $(find "$INSTALL_DIR" -maxdepth 1 -type f | wc -l) Dateien, $(find "$INSTALL_DIR" -maxdepth 1 -type d | wc -l) Verzeichnisse"
}

read_section_value() {
    local file="$1" section="$2" key="$3"
    awk -v s="$section" -v k="$key" '
        $0 ~ "^  " s ":" { found = 1; next }
        found && /^  [a-z]/ { found = 0 }
        found && $0 ~ "^    " k ":" {
            sub(/^    [^:]+:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            print
        }
    ' "$file" | head -1
}

config_wizard() {
    if [ "$UPDATE_MODE" = true ] && [ "$CONFIG_CHOICE" = "keep" ]; then
        log "Bestehende Konfiguration wird verwendet."
        return
    fi

    header "Konfiguration"

    local cfg="$INSTALL_DIR/default_config.yaml"
    if [ ! -f "$cfg" ]; then
        warn "Keine default_config.yaml gefunden unter $cfg"
        warn "Überspringe Konfigurationsassistent."
        return
    fi

    CONFIG_FILE="$INSTALL_DIR/config.yaml"
    : > "$CONFIG_FILE"

    echo -e "${YELLOW}Im Folgenden kannst du die wichtigsten Einstellungen vornehmen.${NC}"
    echo -e "${YELLOW}Drücke einfach Enter, um den jeweiligen Standardwert zu übernehmen.${NC}\n"

    # --- MQTT ---
    echo -e "${BOLD}${BLUE}┌─ MQTT (Message Broker) ─────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}Ohne MQTT-Broker läuft nichts. Hier die Zugangsdaten.${NC}"

    local _v
    _v=$(read_section_value "$cfg" "mqtt" "host");    ask "MQTT Broker Host"         "${_v:-192.168.1.5}" MQTT_HOST
    _v=$(read_section_value "$cfg" "mqtt" "port");    ask "MQTT Broker Port"         "${_v:-1883}"         MQTT_PORT
    _v=$(read_section_value "$cfg" "mqtt" "baseOutTopic"); ask "MQTT Base Out Topic" "${_v:-home/raspi}"   MQTT_OUT
    _v=$(read_section_value "$cfg" "mqtt" "inTopic"); ask "MQTT In Topic"            "${_v:-home/raspi}"   MQTT_IN

    cat > "$CONFIG_FILE" <<YAML
services:
  mqtt:
    host: $MQTT_HOST
    port: $MQTT_PORT
    baseOutTopic: $MQTT_OUT
    inTopic: $MQTT_IN
YAML

    # --- Temperature ---
    echo -e "\n${BOLD}${BLUE}┌─ Temperatursensor (DHT22/AM2302) ───────────────────┐${NC}"
    if confirm "Temperatursensor aktivieren?" "n" TEMP_ACTIVE; then
        _v=$(read_section_value "$cfg" "temperature" "gpioPin");        ask "  GPIO-Pin"               "${_v:-4}"    TEMP_PIN
        _v=$(read_section_value "$cfg" "temperature" "sensorType");     ask "  Sensor-Typ (DHT22/DHT11)" "${_v:-DHT22}" TEMP_TYPE
        _v=$(read_section_value "$cfg" "temperature" "pollInterval");   ask "  Poll-Intervall (Sekunden)" "${_v:-30}"  TEMP_INTERVAL

        cat >> "$CONFIG_FILE" <<YAML
  temperature:
    active: True
    gpioPin: $TEMP_PIN
    sensorType: "$TEMP_TYPE"
    pollInterval: $TEMP_INTERVAL
YAML
    fi

    # --- Binary Sensor ---
    echo -e "\n${BOLD}${BLUE}┌─ Binärsensoren (Reed, PIR) ────────────────────────┐${NC}"
    if confirm "Binärsensoren aktivieren?" "n" BIN_ACTIVE; then
        local sensors_block sensor_tmp="$TMPDIR/binary_sensors.yaml"
        sensors_block=$(sed -n '/^  binarySensor:/,/^  [a-z]/p' "$cfg")
        : > "$sensor_tmp"

        local sensor_id sensor_pin
        while IFS= read -r sensor_line; do
            if echo "$sensor_line" | grep -qE '^\s+- id:'; then
                sensor_id=$(echo "$sensor_line" | sed 's/.*id:[[:space:]]*"\([^"]*\)".*/\1/')
                sensor_pin=$(echo "$sensors_block" | grep -A1 "$sensor_line" | grep "gpioPin" | sed 's/.*gpioPin:[[:space:]]*//')
                sensor_pin="${sensor_pin:-21}"
                echo -e "  ${YELLOW}Sensor: $sensor_id${NC}"
                ask "  GPIO-Pin für '$sensor_id'" "$sensor_pin" BIN_PIN
                cat >> "$sensor_tmp" <<YAML
      - id: "$sensor_id"
        gpioPin: $BIN_PIN
YAML
            fi
        done <<< "$sensors_block"

        cat >> "$CONFIG_FILE" <<YAML
  binarySensor:
    active: True
    sensors:
YAML
        cat "$sensor_tmp" >> "$CONFIG_FILE"
    fi

    # --- Update ---
    echo -e "\n${BOLD}${BLUE}┌─ Update-Einstellungen ─────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}Automatische Updates für Homuncu-Pi und System.${NC}"

    ask "Auto-Update (Off/System/Homuncu/All)" "Off" AUTOUPDATE

    cat >> "$CONFIG_FILE" <<YAML
  update:
    active: True
    repoUrl: "${BASE_URL}"
    type: ${CHANNEL}
    autoupdate: "$AUTOUPDATE"
YAML

    # --- Optional services ---
    echo -e "\n${BOLD}${BLUE}┌─ Weitere optionale Dienste ────────────────────────┐${NC}"
    echo -e "  ${YELLOW}Diese Dienste kannst du später jederzeit in der config.yaml aktivieren.${NC}"

    if confirm "RFID-Leser (RC522) aktivieren?" "n" RFID_ACTIVE; then
        _v=$(read_section_value "$cfg" "rfid" "apiEndpoint")
        ask "  API-Endpoint für RFID-Events" "${_v:-http://my-service.local/api/rfid}" RFID_ENDPOINT
        cat >> "$CONFIG_FILE" <<YAML
  rfid:
    active: True
    apiEndpoint: "${RFID_ENDPOINT}"
YAML
    fi

    if confirm "WS2812B-LED-Streifen aktivieren?" "n" WS2812_ACTIVE; then
        _v=$(read_section_value "$cfg" "ws2812" "gpioPin"); ask "  GPIO-Pin"    "${_v:-18}" WS_PIN
        _v=$(read_section_value "$cfg" "ws2812" "numLeds"); ask "  Anzahl LEDs"  "${_v:-0}"  WS_LEDS
        cat >> "$CONFIG_FILE" <<YAML
  ws2812:
    active: True
    gpioPin: $WS_PIN
    numLeds: $WS_LEDS
YAML
    fi

    if confirm "WLED-Controller aktivieren?" "n" WLED_ACTIVE; then
        _v=$(sed -n '/^  wled:/,/^  [a-z]/s/^      - name:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg")
        ask "  Geräte-Name" "${_v:-device1}" WLED_NAME
        _v=$(sed -n '/^  wled:/,/^  [a-z]/s/^      - ip:[[:space:]]*//p' "$cfg")
        ask "  IP-Adresse" "${_v:-192.168.1.123}" WLED_IP
        cat >> "$CONFIG_FILE" <<YAML
  wled:
    active: True
    devices:
      - name: "${WLED_NAME}"
        ip: ${WLED_IP}
YAML
    fi

    # --- Camera ---
    echo -e "\n${BOLD}${BLUE}┌─ Kamera (Raspberry Pi / libcamera) ────────────────┐${NC}"
    if confirm "Kamera-Service aktivieren?" "n" CAM_ACTIVE; then
        _v=$(read_section_value "$cfg" "camera" "resolution" | tr -d '[] ' || true)
        ask "  Auflösung (Breite,Höhe)" "${_v:-1920,1080}" CAM_RES
        _v=$(read_section_value "$cfg" "camera" "quality");   ask "  JPEG-Qualität (1-100)"     "${_v:-85}"                CAM_QUALITY
        _v=$(read_section_value "$cfg" "camera" "storagePath"); ask "  Speicherpfad"            "${_v:-/tmp/camera}"       CAM_PATH
        _v=$(read_section_value "$cfg" "camera" "mqttTopic"); ask "  MQTT-Topic"                "${_v:-camera}"            CAM_TOPIC
        _v=$(read_section_value "$cfg" "camera" "mqttFlags"); ask "  MQTT-Flags"                "${_v:-ADD_BASE_TOPIC,ADD_HOSTNAME,ADD_TIMESTAMP}" CAM_FLAGS

        CAM_RES=$(echo "$CAM_RES" | tr -d ' ')
        cat >> "$CONFIG_FILE" <<YAML
  camera:
    active: True
    resolution: [${CAM_RES%,*}, ${CAM_RES#*,}]
    quality: $CAM_QUALITY
    storagePath: "${CAM_PATH}"
    mqttTopic: "${CAM_TOPIC}"
    mqttFlags: "${CAM_FLAGS}"
YAML
    fi

    log "Konfiguration erstellt: ${BOLD}$CONFIG_FILE${NC}"
}

print_summary() {
    if [ "$CONFIG_ONLY" = true ]; then
        header "Config-Anpassung abgeschlossen!"
        echo -e "${GREEN}Die Konfiguration wurde aktualisiert.${NC}\n"
    elif [ "$UPDATE_MODE" = true ]; then
        header "Update abgeschlossen!"
        echo -e "${GREEN}Homuncu-Pi wurde erfolgreich aktualisiert!${NC}\n"
        echo -e "${BOLD}Alte Version:${NC}            $LOCAL_VERSION"
        echo -e "${BOLD}Neue Version:${NC}            $REMOTE_VERSION"
    else
        header "Installation abgeschlossen!"
        echo -e "${GREEN}Homuncu-Pi wurde erfolgreich installiert!${NC}\n"
    fi

    echo -e "${BOLD}Installationsverzeichnis:${NC}  $INSTALL_DIR"
    if [ -n "${CHANNEL:-}" ]; then
        echo -e "${BOLD}Channel:${NC}                  $CHANNEL (${REMOTE_VERSION:-?})"
    fi
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BOLD}Konfiguration:${NC}          $CONFIG_FILE"
    fi

    if [ "$CONFIG_ONLY" != true ]; then
        echo ""
        echo -e "${BOLD}${GREEN}Nächste Schritte:${NC}"
        echo -e "  ${BOLD}1.${NC} Zum Verzeichnis wechseln:  ${YELLOW}cd $INSTALL_DIR${NC}"
        echo -e "  ${BOLD}2.${NC} Homuncu-Pi starten:        ${YELLOW}./run.sh${NC}"
        echo -e "  ${BOLD}3.${NC} Als Systemdienst:           ${YELLOW}./service.sh install${NC}"
        echo ""
        echo -e "  ${YELLOW}Tipp:${NC} Die config.yaml kannst du jederzeit bearbeiten."
        echo -e "  Ein Neustart von Homuncu-Pi ist dann erforderlich.\n"
    fi
}

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --answer-file)
                shift
                load_answers_file "$1"
                ;;
            --set)
                shift
                local key="${1%%=*}" value="${1#*=}"
                _A["$key"]="$value"
                ;;
            *)  error "Unbekannter Parameter: $1"; exit 1 ;;
        esac
        shift
    done

    detect_downloader
    print_logo
    welcome

    TMPDIR=$(mktemp -d)

    get_install_dir
    check_existing_installation

    get_base_url
    get_channel

    if [ "$CONFIG_ONLY" != true ]; then
        fetch_version

        if [ "$UPDATE_MODE" = true ] && [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
            warn "Die installierte Version entspricht der Remote-Version."
            if ! confirm "Trotzdem fortfahren (Neuinstallation)?" "n" FORCE; then
                log "Update abgebrochen."
                exit 0
            fi
        fi

        download_archive
        extract_archive
    fi

    config_wizard
    print_summary
}

main "$@"
