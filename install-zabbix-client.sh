#!/bin/bash
# =============================================================================
# Script d'installation de l'agent Zabbix 7.0 sur Ubuntu Server 24.04
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
ZABBIX_SERVER_IP="192.168.10.4"
ZABBIX_DEB="zabbix-release_latest_7.0+ubuntu24.04_all.deb"
ZABBIX_DEB_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/${ZABBIX_DEB}"
ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"
LOCAL_HOSTNAME=$(hostname)

# --- Couleurs ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Fonctions ---------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root (sudo)."
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Impossible de détecter l'OS."
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "24.04" ]]; then
        log_warn "OS détecté : $PRETTY_NAME — ce script est prévu pour Ubuntu 24.04."
        read -rp "Continuer quand même ? (o/N) : " confirm
        [[ "$confirm" =~ ^[oO]$ ]] || exit 0
    else
        log_success "OS détecté : $PRETTY_NAME"
    fi
}

# --- Début du script ---------------------------------------------------------
clear
echo -e "${BLUE}"
echo "============================================="
echo "   Installation Zabbix Agent 7.0"
echo "   Ubuntu Server 24.04"
echo "============================================="
echo -e "${NC}"

check_root
check_os

# Étape 1 — Téléchargement du paquet de dépôt
log_info "Étape 1/5 — Téléchargement du dépôt Zabbix 7.0..."
wget -q --show-progress -O "/tmp/${ZABBIX_DEB}" "${ZABBIX_DEB_URL}" \
    || log_error "Échec du téléchargement. Vérifiez votre connexion."
log_success "Paquet téléchargé."

# Étape 2 — Installation du dépôt
log_info "Étape 2/5 — Installation du dépôt Zabbix..."
dpkg -i "/tmp/${ZABBIX_DEB}" \
    || log_error "Échec de l'installation du paquet de dépôt."
apt update -qq
log_success "Dépôt Zabbix ajouté et mis à jour."

# Étape 3 — Installation de l'agent
log_info "Étape 3/5 — Installation de zabbix-agent..."
apt install -y zabbix-agent \
    || log_error "Échec de l'installation de zabbix-agent."
log_success "zabbix-agent installé."

# Étape 4 — Configuration
log_info "Étape 4/5 — Configuration de l'agent..."
log_info "  Serveur Zabbix : ${ZABBIX_SERVER_IP}"
log_info "  Hostname local : ${LOCAL_HOSTNAME}"

# Sauvegarde du fichier de conf original
cp "${ZABBIX_CONF}" "${ZABBIX_CONF}.bak"
log_success "Sauvegarde créée : ${ZABBIX_CONF}.bak"

# Remplacement des valeurs dans le fichier de configuration
sed -i "s/^Server=.*/Server=${ZABBIX_SERVER_IP}/"             "${ZABBIX_CONF}"
sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER_IP}/" "${ZABBIX_CONF}"
sed -i "s/^Hostname=.*/Hostname=${LOCAL_HOSTNAME}/"           "${ZABBIX_CONF}"

log_success "Configuration appliquée."

# Étape 5 — Démarrage et activation du service
log_info "Étape 5/5 — Démarrage et activation du service..."
systemctl restart zabbix-agent
systemctl enable zabbix-agent
log_success "Service zabbix-agent démarré et activé."

# --- Résumé ------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================="
echo "   Installation terminée avec succès !"
echo "=============================================${NC}"
echo ""
echo -e "  ${BLUE}Serveur Zabbix${NC}  : ${ZABBIX_SERVER_IP}"
echo -e "  ${BLUE}Hostname agent${NC}  : ${LOCAL_HOSTNAME}"
echo -e "  ${BLUE}Config${NC}          : ${ZABBIX_CONF}"
echo -e "  ${BLUE}Backup config${NC}   : ${ZABBIX_CONF}.bak"
echo ""
echo -e "  Statut du service :"
systemctl status zabbix-agent --no-pager -l | grep -E "Active:|Loaded:"
echo ""
echo -e "${YELLOW}  N'oublie pas d'ajouter cet hôte dans l'interface Zabbix !${NC}"
echo ""

# Nettoyage
rm -f "/tmp/${ZABBIX_DEB}"