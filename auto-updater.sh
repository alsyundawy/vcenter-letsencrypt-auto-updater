#!/bin/bash

################################################################################
# vCenter/PSC SSL Certificate Updater (Enhanced & Optimized)
# Automatically updates LetsEncrypt certificates for vCenter Appliance
#
# Original: Copyright (c) 2018 - Rob Thomas - xrobau@linux.com
# Enhanced: 2026 - Security hardening, error handling, logging, modern best practices
#
# Licensed under GNU General Public License v3.0
# For more information: https://wiki.9r.com.au/display/9R/LetsEncrypt+Certificates+for+vCenter+and+PSC
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_FILE="/root/.acme.sh/update.conf"
readonly CERT_LIVE="/etc/vmware-rhttpproxy/ssl/rui.crt"
readonly LOG_FILE="/var/log/vcenter-cert-updater.log"
readonly LOCK_FILE="/var/run/vcenter-cert-updater.lock"
readonly ROOT_CERT_URL="https://letsencrypt.org/certs/isrgrootx1.pem"
readonly ROOT_CERT_SHA256="ca3b0a7d13e46db83ba890b415e5aadf7fbbb914cefd4f3f2cb193fb2df51f42"  # ISRGRootX1 certificate fingerprint
readonly TIMEOUT="30"  # Timeout for curl operations in seconds
readonly LOG_RETENTION_DAYS="30"  # Keep logs for 30 days

# Color output for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'  # No Color

################################################################################
# Logging Functions
################################################################################
log_info() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $message" | tee -a "$LOG_FILE"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $message${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $message${NC}" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $message${NC}" | tee -a "$LOG_FILE"
}

################################################################################
# Cleanup & Lock Management
################################################################################
cleanup() {
    local exit_code=$?
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code: $exit_code"
    fi
    exit "$exit_code"
}

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: $pid)"
            exit 1
        fi
    fi
    echo "$$" > "$LOCK_FILE"
}

rotate_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        find /var/log -name "vcenter-cert-updater*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    fi
}

trap cleanup EXIT

################################################################################
# Validation Functions
################################################################################
validate_config() {
    log_info "Validating configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Please create it with the following content:"
        log_error "  CERTNAME='your.domain.name'"
        log_error "  ADMINACCOUNT='administrator@vsphere.local'"
        log_error "  ADMINPASS='your_password'"
        exit 1
    fi
    
    # Source config file with safety checks
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        log_error "Failed to source configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate required variables
    for var in CERTNAME ADMINACCOUNT ADMINPASS; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable '$var' not set in $CONFIG_FILE"
            exit 1
        fi
    done
    
    # Validate certificate existence
    local cert_path="/root/.acme.sh/$CERTNAME/${CERTNAME}.cer"
    if [[ ! -f "$cert_path" ]]; then
        log_error "Certificate not found: $cert_path"
        log_error "Is acme.sh properly configured with domain: $CERTNAME?"
        exit 1
    fi
    
    log_info "Configuration validation successful"
}

validate_cert_live() {
    if [[ ! -f "$CERT_LIVE" ]]; then
        log_error "Current certificate not found: $CERT_LIVE"
        exit 1
    fi
}

################################################################################
# Hash Computation (SHA256 instead of deprecated MD5)
################################################################################
compute_hash() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File not found for hashing: $file"
        return 1
    fi
    sha256sum "$file" | cut -d' ' -f1
}

check_cert_update_needed() {
    log_info "Comparing certificates (SHA256)..."
    
    local live_hash
    local current_hash
    
    live_hash=$(compute_hash "$CERT_LIVE") || return 1
    current_hash=$(compute_hash "/root/.acme.sh/$CERTNAME/${CERTNAME}.cer") || return 1
    
    log_info "Current certificate hash: $current_hash"
    log_info "Live certificate hash:    $live_hash"
    
    if [[ "$live_hash" == "$current_hash" ]]; then
        log_info "Certificate is up to date. No update needed."
        return 1
    fi
    
    return 0
}

################################################################################
# Certificate Chain Download
################################################################################
download_root_cert() {
    local cert_path="$1"
    local temp_cert
    
    log_info "Downloading Let's Encrypt root certificate..."
    
    temp_cert=$(mktemp) || {
        log_error "Failed to create temporary file for root certificate"
        return 1
    }
    
    # Download with timeout and retry logic
    if ! curl -fsSL \
        --max-time "$TIMEOUT" \
        --retry 3 \
        --retry-delay 2 \
        --output "$temp_cert" \
        "$ROOT_CERT_URL"; then
        log_error "Failed to download root certificate from $ROOT_CERT_URL"
        rm -f "$temp_cert"
        return 1
    fi
    
    # Validate certificate
    if ! openssl x509 -in "$temp_cert" -noout 2>/dev/null; then
        log_error "Downloaded file is not a valid X.509 certificate"
        rm -f "$temp_cert"
        return 1
    fi
    
    # Move to destination
    mv "$temp_cert" "$cert_path" || {
        log_error "Failed to write root certificate to $cert_path"
        rm -f "$temp_cert"
        return 1
    }
    
    log_success "Root certificate downloaded and validated"
    return 0
}

build_fullchain() {
    local cert_name="$1"
    local acme_dir="/root/.acme.sh/$cert_name"
    local fullchain="${acme_dir}/fullchain.cer"
    local fullchain_with_root="${acme_dir}/fullchainwithroot.cer"
    
    log_info "Building certificate chain..."
    
    if [[ ! -f "$fullchain" ]]; then
        log_error "Full chain certificate not found: $fullchain"
        return 1
    fi
    
    # Create new chain file with root certificate
    if ! download_root_cert "$fullchain_with_root"; then
        log_error "Failed to build certificate chain with root"
        return 1
    fi
    
    # Append fullchain to root certificate
    if ! cat "$fullchain" >> "$fullchain_with_root"; then
        log_error "Failed to append fullchain to root certificate"
        return 1
    fi
    
    # Validate the combined chain
    if ! openssl crl2pkcs7 -nocrl -certfile "$fullchain_with_root" -outform PEM 2>/dev/null > /dev/null; then
        log_warn "Certificate chain validation warning (may still be usable)"
    fi
    
    log_success "Certificate chain built successfully"
    return 0
}

################################################################################
# Certificate Update
################################################################################
update_certificate() {
    local cert_name="$1"
    local admin_account="$2"
    local admin_pass="$3"
    local acme_dir="/root/.acme.sh/$cert_name"
    local cert_path="${acme_dir}/${cert_name}.cer"
    local key_path="${acme_dir}/${cert_name}.key"
    local chain_path="${acme_dir}/fullchainwithroot.cer"
    
    # Validate certificate files
    for file in "$cert_path" "$key_path" "$chain_path"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required certificate file not found: $file"
            return 1
        fi
    done
    
    log_info "Updating vCenter certificate..."
    log_info "Certificate: $cert_path"
    log_info "Key: $key_path"
    log_info "Chain: $chain_path"
    
    # Use certificate-manager with input automation
    # Menu: 1 = vCenter, 2 = Replace certificate
    if ! (
        printf '1\n%s\n' "$admin_account"
        sleep 1
        printf '%s\n' "$admin_pass"
        sleep 1
        printf '2\n'
        sleep 1
        printf '%s\n%s\n%s\ny\n\n' "$cert_path" "$key_path" "$chain_path"
        sleep 2
    ) | setsid /usr/lib/vmware-vmca/bin/certificate-manager 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Certificate manager update failed"
        return 1
    fi
    
    sleep 5
    log_success "Certificate update completed"
    return 0
}

################################################################################
# Load vCenter Environment
################################################################################
load_vcenter_env() {
    log_info "Loading vCenter environment variables..."
    
    local env_file="/etc/sysconfig/vmware-environment"
    
    if [[ ! -f "$env_file" ]]; then
        log_warn "vCenter environment file not found: $env_file"
        return 0
    fi
    
    # Safely source environment file
    eval "$(awk '{if ($0 ~ /^[A-Za-z_]/ && $0 !~ /^#/) print "export " $0}' "$env_file" 2>/dev/null || true)"
    
    log_info "Environment variables loaded"
}

################################################################################
# Main Execution
################################################################################
main() {
    acquire_lock
    rotate_logs
    
    log_info "=== vCenter Certificate Auto-Updater Started ==="
    log_info "Script version: 2.0 (Enhanced & Optimized)"
    log_info "Current user: $(whoami)"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Validation phase
    validate_config
    validate_cert_live
    load_vcenter_env
    
    # Check if update is needed
    if ! check_cert_update_needed; then
        log_info "No certificate update required"
        exit 0
    fi
    
    # Build certificate chain
    if ! build_fullchain "$CERTNAME"; then
        log_error "Failed to build certificate chain"
        exit 1
    fi
    
    # Update certificate
    if ! update_certificate "$CERTNAME" "$ADMINACCOUNT" "$ADMINPASS"; then
        log_error "Failed to update certificate"
        exit 1
    fi
    
    log_success "=== Certificate update process completed successfully ==="
    exit 0
}

# Execute main function
main "$@"
