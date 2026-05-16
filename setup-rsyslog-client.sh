#!/bin/bash
#=============================================================================
# Script de configuration rsyslog - Client SSM
# Configure le forwarding des logs vers le serveur Graylog
# Compatible Ubuntu Server 22.04 / 24.04
#=============================================================================

set -e

# ========================
# CONFIGURATION
# ========================
GRAYLOG_IP="192.168.10.8"
GRAYLOG_PORT="1514"
RSYSLOG_CONF="/etc/rsyslog.d/60-forward-graylog.conf"
QUEUE_MAX_DISK="500m"

# ========================
# COULEURS
# ========================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========================
# FONCTIONS
# ========================
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_err()  { echo -e "${RED}[ERREUR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ========================
# VÉRIFICATIONS
# ========================

# Vérifier les droits root
if [[ $EUID -ne 0 ]]; then
    log_err "Ce script doit être exécuté en tant que root (sudo)."
    exit 1
fi

# Vérifier que rsyslog est installé
if ! command -v rsyslogd &> /dev/null; then
    log_warn "rsyslog n'est pas installé. Installation en cours..."
    apt-get update -qq && apt-get install -y -qq rsyslog
    log_ok "rsyslog installé."
fi

# Vérifier que rsyslog tourne
if ! systemctl is-active --quiet rsyslog; then
    log_warn "rsyslog n'est pas actif. Démarrage..."
    systemctl start rsyslog
    systemctl enable rsyslog
fi

log_ok "rsyslog est installé et actif (version : $(rsyslogd -v | head -1))"

# ========================
# SAUVEGARDE
# ========================
if [[ -f "$RSYSLOG_CONF" ]]; then
    BACKUP="${RSYSLOG_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$RSYSLOG_CONF" "$BACKUP"
    log_warn "Configuration existante sauvegardée dans $BACKUP"
fi

# ========================
# CONFIGURATION RSYSLOG
# ========================
log_warn "Création de la configuration de forwarding vers Graylog..."

cat > "$RSYSLOG_CONF" << EOF
#=============================================================================
# Configuration rsyslog - Forwarding vers Graylog (SSM)
# Généré automatiquement le $(date '+%Y-%m-%d %H:%M:%S')
# Serveur : $(hostname)
#=============================================================================

# Template au format RFC 5424 (syslog moderne)
template(name="GraylogFormat" type="string"
    string="<%PRI%>%PROTOCOL-VERSION% %TIMESTAMP:::date-rfc3339% %HOSTNAME% %APP-NAME% %PROCID% %MSGID% %STRUCTURED-DATA% %msg%\n"
)

# Forwarding de tous les logs vers Graylog en TCP
action(
    type="omfwd"
    target="${GRAYLOG_IP}"
    port="${GRAYLOG_PORT}"
    protocol="tcp"
    template="GraylogFormat"

    # File d'attente sur disque en cas d'indisponibilité du serveur
    queue.type="LinkedList"
    queue.filename="fwd_graylog"
    queue.maxDiskSpace="${QUEUE_MAX_DISK}"
    queue.saveOnShutdown="on"
    action.resumeRetryCount="-1"
)
EOF

log_ok "Configuration créée dans $RSYSLOG_CONF"

# ========================
# VALIDATION
# ========================
log_warn "Validation de la configuration rsyslog..."

if rsyslogd -N1 2>&1 | grep -q "error"; then
    log_err "La configuration contient des erreurs :"
    rsyslogd -N1
    exit 1
fi

log_ok "Configuration valide."

# ========================
# REDÉMARRAGE
# ========================
log_warn "Redémarrage de rsyslog..."
systemctl restart rsyslog

if systemctl is-active --quiet rsyslog; then
    log_ok "rsyslog redémarré avec succès."
else
    log_err "rsyslog n'a pas pu redémarrer. Vérifiez les logs avec : journalctl -u rsyslog"
    exit 1
fi

# ========================
# TEST
# ========================
log_warn "Envoi d'un message de test vers Graylog..."
logger -t rsyslog-setup "Configuration rsyslog terminee sur $(hostname) - forwarding vers ${GRAYLOG_IP}:${GRAYLOG_PORT}"
log_ok "Message de test envoyé. Vérifiez dans Graylog que le message apparaît pour $(hostname)."

# ========================
# RÉSUMÉ
# ========================
echo ""
echo "========================================"
echo " Configuration terminée"
echo "========================================"
echo " Serveur      : $(hostname)"
echo " Graylog      : ${GRAYLOG_IP}:${GRAYLOG_PORT}"
echo " Protocole    : TCP"
echo " Fichier conf : ${RSYSLOG_CONF}"
echo " Queue disque : ${QUEUE_MAX_DISK}"
echo "========================================"
echo ""
