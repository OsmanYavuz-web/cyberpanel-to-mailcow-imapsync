#!/usr/bin/env bash
#
# CyberPanel → Mailcow IMAP Sync Migration Script
# Geliştirici: Osman Yavuz
# GitHub: https://github.com/OsmanYavuz-web/
# Repository: https://github.com/OsmanYavuz-web/cyberpanel-to-mailcow-imapsync
#
set -o pipefail

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; NC="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_LOG="$SCRIPT_DIR/migration_full.log"
FAIL_LOG="$SCRIPT_DIR/FAILED_PASSWORDS.txt"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"
echo "=== CyberPanel → Mailcow Migration Log ===" > "$MAIN_LOG"
echo "Başlangıç: $(date)" >> "$MAIN_LOG"
echo "" >> "$MAIN_LOG"
echo "" > "$FAIL_LOG"

echo -e "${BLUE}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  CYBERPANEL → MAILCOW FULL API MIGRATION${NC}"
echo -e "${BLUE}══════════════════════════════════════════${NC}"

# ---------------------------------------------------------
# PARAMETRELER
# ---------------------------------------------------------

if [ $# -lt 6 ]; then
  echo -e "${YELLOW}Kullanım:${NC}"
  echo "$0 CYBERPANEL_IP SSH_USER SSH_PASS MYSQL_PASS MAILCOW_API_KEY MAILCOW_HOSTNAME"
  exit 1
fi

CP_IP="$1"
CP_SSH_USER="$2"
CP_SSH_PASS="$3"
CP_MYSQL_PASS="$4"
MAILCOW_API_KEY="$5"
MAILCOW_HOSTNAME="$6"

MAILCOW_SERVER="https://$MAILCOW_HOSTNAME/api"

CP_IMAP_PORT=993
MAILCOW_IMAP_HOST="dovecot-mailcow"
MAILCOW_IMAP_PORT=993

# ---------------------------------------------------------
# CyberPanel IMAP şifresi
# ---------------------------------------------------------
echo -ne "${YELLOW}CyberPanel IMAP Şifresi: ${NC}"
read -r CP_IMAP_PASS
echo ""

[ -z "$CP_IMAP_PASS" ] && { echo -e "${RED}Şifre boş olamaz.${NC}"; exit 1; }

# ---------------------------------------------------------
# Mailcow için şifre
# ---------------------------------------------------------
echo -ne "${YELLOW}Mailcow için verilecek yeni şifre: ${NC}"
read -r MAILCOW_NEW_PASS
echo ""

[ -z "$MAILCOW_NEW_PASS" ] && { echo -e "${RED}Boş şifre olmaz.${NC}"; exit 1; }

# ---------------------------------------------------------
# Başlangıç soruları
# ---------------------------------------------------------
echo -ne "${YELLOW}Domainleri Mailcow'a eklemek istiyor musun? (E/H): ${NC}"
read -r DOMAIN_CONFIRM
[[ "$DOMAIN_CONFIRM" =~ ^[Ee]$ ]] && DO_DOMAIN_IMPORT=1 || DO_DOMAIN_IMPORT=0

echo -ne "${YELLOW}Mailboxları migrate etmek istiyor musun? (E/H): ${NC}"
read -r MAILBOX_CONFIRM
[[ "$MAILBOX_CONFIRM" =~ ^[Ee]$ ]] && DO_MAILBOX_IMPORT=1 || DO_MAILBOX_IMPORT=0
echo ""

# ---------------------------------------------------------
# Ortam testleri
# ---------------------------------------------------------
command -v sshpass >/dev/null || { 
  echo -e "${RED}sshpass eksik${NC}"
  echo -e "${YELLOW}Kurulum: sudo apt-get install sshpass${NC}"
  exit 1
}
command -v docker   >/dev/null || { echo -e "${RED}Docker yok${NC}"; exit 1; }
command -v curl     >/dev/null || { echo -e "${RED}curl eksik${NC}"; exit 1; }

SSH_CMD="sshpass -p '$CP_SSH_PASS' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5"

echo -e "${YELLOW}[*] SSH test...${NC}"
if eval "$SSH_CMD $CP_SSH_USER@$CP_IP echo OK" >/dev/null 2>>"$MAIN_LOG"; then
  echo -e "${GREEN}✓ SSH OK${NC}"
  echo "[OK] SSH bağlantısı başarılı" >> "$MAIN_LOG"
else
  echo -e "${RED}SSH FAIL${NC}"
  echo "[HATA] SSH bağlantısı başarısız" >> "$MAIN_LOG"
  exit 1
fi

# ---------------------------------------------------------
# Kullanıcıları çek
# ---------------------------------------------------------

TMPFILE="/dev/shm/cp_accounts.txt"

echo -e "${YELLOW}[*] Kullanıcılar alınıyor...${NC}"
eval "$SSH_CMD $CP_SSH_USER@$CP_IP \"mysql -ucyberpanel -p'$CP_MYSQL_PASS' cyberpanel -N -e 'SELECT email,password FROM e_users;'\"" \
  > "$TMPFILE" 2>>"$MAIN_LOG"

[ ! -s "$TMPFILE" ] && { echo -e "${RED}Kullanıcı listesi alınamadı.${NC}"; exit 1; }

USER_COUNT=$(wc -l < "$TMPFILE")
echo -e "${GREEN}✓ $USER_COUNT kullanıcı bulundu${NC}"
echo "[OK] $USER_COUNT kullanıcı bulundu" >> "$MAIN_LOG"
echo ""

# ---------------------------------------------------------
# Domain ekleme (API, 100 mailbox / 100 alias, toplam quota 1TB)
# ---------------------------------------------------------

if [ $DO_DOMAIN_IMPORT -eq 1 ]; then
  echo -e "${YELLOW}[*] Domain import başlıyor...${NC}"
  echo "[*] Domain import başlıyor..." >> "$MAIN_LOG"

  DOMAINS=$(awk '{print $1}' "$TMPFILE" | awk -F@ '{print $2}' | sort -u)

  for D in $DOMAINS; do
    echo -ne " → $D ekleniyor..."

    RESPONSE=$(curl -k -s -X POST "$MAILCOW_SERVER/v1/add/domain" \
      -H "X-API-Key: $MAILCOW_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"active\": \"1\",
        \"domain\": \"$D\",
        \"description\": \"\",
        \"aliases\": \"100\",
        \"mailboxes\": \"100\",
        \"maxquota\": \"10240\",
        \"defquota\": \"10240\",
        \"quota\": \"102400\",
        \"backupmx\": \"0\",
        \"relay_all_recipients\": \"0\",
        \"rl_frame\": \"s\",
        \"rl_value\": \"10\"
      }")

    if echo "$RESPONSE" | grep -q "mailbox"; then
      echo -e " ${GREEN}OK${NC}"
      echo "[OK] Domain eklendi: $D" >> "$MAIN_LOG"
    else
      echo -e " ${RED}HATA${NC}"
      echo "[HATA] Domain eklenemedi: $D - $RESPONSE" >> "$MAIN_LOG"
    fi
  done

  echo ""
else
  echo -e "${YELLOW}Domain import SKIP${NC}"
  echo "[SKIP] Domain import atlandı" >> "$MAIN_LOG"
  echo ""
fi

# ---------------------------------------------------------
# MIGRATION LOOP
# ---------------------------------------------------------
if [ $DO_MAILBOX_IMPORT -eq 1 ]; then
  echo -e "${YELLOW}[*] Mailbox migration başlıyor...${NC}"

  exec 3< "$TMPFILE"
  while IFS=$'\t' read -u 3 -r EMAIL HASH; do
    [ -z "$EMAIL" ] && continue

    LOCALPART="${EMAIL%@*}"
    DOMAIN="${EMAIL#*@}"
    SAFE="${EMAIL//[@.]/_}"

    echo -e "${BLUE}────────────────────────────────────────────${NC}"
    echo -e "${GREEN}Hesap: $EMAIL${NC}"

    # Mailbox CREATE
    echo -ne "${YELLOW} → Mailbox oluşturuluyor... ${NC}"

    curl -k -s -X POST "$MAILCOW_SERVER/v1/add/mailbox" \
      -H "X-API-Key: $MAILCOW_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"active\":\"1\",
        \"domain\":\"$DOMAIN\",
        \"local_part\":\"$LOCALPART\",
        \"name\":\"$LOCALPART\",
        \"password\":\"$MAILCOW_NEW_PASS\",
        \"password2\":\"$MAILCOW_NEW_PASS\",
        \"quota\":\"10240\",
        \"force_pw_update\":\"0\"
      }" >/dev/null

    echo -e "${GREEN}OK${NC}"

    # Alias CREATE
    echo -ne "${YELLOW} → Alias ekleniyor... ${NC}"

    curl -k -s -X POST "$MAILCOW_SERVER/v1/add/alias" \
      -H "X-API-Key: $MAILCOW_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"active\":\"1\",
        \"address\":\"$EMAIL\",
        \"goto\":\"$EMAIL\"
      }" >/dev/null

    echo -e "${GREEN}OK${NC}"

    # IMAP test (kaynak)
    echo -ne "${YELLOW} → IMAP test (kaynak)... ${NC}"

    if ! timeout 10 docker run --rm gilleslamiral/imapsync imapsync \
         --host1 "$CP_IP" --port1 "$CP_IMAP_PORT" --ssl1 \
         --user1 "$EMAIL" --password1 "$CP_IMAP_PASS" \
         --dry >/dev/null 2>&1; then

      echo -e "${RED}FAIL${NC}"
      echo "$EMAIL" >> "$FAIL_LOG"
      continue
    fi

    echo -e "${GREEN}OK${NC}"

    # IMAPSYNC
    echo -e "${YELLOW} → IMAPSYNC başlıyor...${NC}"

    if docker run --rm --network mailcowdockerized_mailcow-network gilleslamiral/imapsync imapsync \
          --host1 "$CP_IP" --port1 "$CP_IMAP_PORT" --ssl1 \
          --user1 "$EMAIL" --password1 "$CP_IMAP_PASS" \
          --host2 "$MAILCOW_IMAP_HOST" --port2 "$MAILCOW_IMAP_PORT" --ssl2 \
          --user2 "$EMAIL" --password2 "$MAILCOW_NEW_PASS" \
          --automap --addheader --nofoldersizes --skipsize \
          > "$LOG_DIR/$SAFE.log" 2>&1; then

      echo -e "${GREEN}✓ Migration OK${NC}"
    else
      echo -e "${RED}✗ Migration HATA → $LOG_DIR/$SAFE.log${NC}"
    fi

  done

else
  echo -e "${YELLOW}Mailbox import SKIP${NC}"
  echo "[SKIP] Mailbox import atlandı" >> "$MAIN_LOG"
fi

echo ""
echo -e "${GREEN}=== TAMAMLANDI ===${NC}"
echo "Bitiş: $(date)" >> "$MAIN_LOG"
echo "" >> "$MAIN_LOG"
echo "Genel log: $MAIN_LOG"
echo "Hatalı şifre listesi: $FAIL_LOG"
echo "Log klasörü: $LOG_DIR"
