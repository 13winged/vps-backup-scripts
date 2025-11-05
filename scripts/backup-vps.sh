#!/bin/bash

#
# VPS Backup Script
# Полное резервное копирование системы
# GitHub: https://github.com/13winged/vps-backup-scripts
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../config" ]; then
    source "${SCRIPT_DIR}/../config"
else
    echo "⚠️  Config file not found. Using defaults."
fi

# Default configuration
BACKUP_DIR="${BACKUP_DIR:-/backup}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="${LOG_FILE:-/var/log/vps-backup.log}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
BACKUP_MYSQL="${BACKUP_MYSQL:-true}"
BACKUP_POSTGRES="${BACKUP_POSTGRES:-true}"
BACKUP_WEB_DIRS="${BACKUP_WEB_DIRS:-true}"
BACKUP_SYSTEM_FILES="${BACKUP_SYSTEM_FILES:-true}"

# Variables
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="vps-backup-${DATE}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check disk space
    local available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
        warn "⚠️  Low disk space available: ${available_space}KB"
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" || error "Failed to create backup directory"
    
    # Check required tools
    command -v tar >/dev/null 2>&1 || error "tar is required but not installed"
    command -v gzip >/dev/null 2>&1 || error "gzip is required but not installed"
}

# Backup system files
backup_system_files() {
    if [ "$BACKUP_SYSTEM_FILES" != "true" ]; then
        info "📁 System files backup skipped (config)"
        return 0
    fi
    
    log "📁 Backing up system files..."
    
    mkdir -p "${BACKUP_PATH}/system"
    
    # /etc directory
    if [ -d "/etc" ]; then
        log "  → /etc configuration files"
        tar -czf "${BACKUP_PATH}/system/etc.tar.gz" -C / etc/ 2>/dev/null || warn "Failed to backup /etc"
    fi
    
    # /home directories
    if [ -d "/home" ]; then
        log "  → /home directories"
        tar -czf "${BACKUP_PATH}/system/home.tar.gz" -C / home/ 2>/dev/null || warn "Failed to backup /home"
    fi
    
    # /root directory
    if [ -d "/root" ]; then
        log "  → /root directory"
        tar -czf "${BACKUP_PATH}/system/root.tar.gz" -C / root/ 2>/dev/null || warn "Failed to backup /root"
    fi
    
    # Package lists
    log "  → Package lists"
    if command -v dpkg >/dev/null; then
        dpkg --get-selections > "${BACKUP_PATH}/system/packages-dpkg.list"
    fi
    if command -v rpm >/dev/null; then
        rpm -qa > "${BACKUP_PATH}/system/packages-rpm.list"
    fi
    
    # System info
    echo "=== System Information ===" > "${BACKUP_PATH}/system/system-info.txt"
    echo "Hostname: $(hostname)" >> "${BACKUP_PATH}/system/system-info.txt"
    echo "Kernel: $(uname -r)" >> "${BACKUP_PATH}/system/system-info.txt"
    echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2)" >> "${BACKUP_PATH}/system/system-info.txt"
    echo "Backup Date: $(date)" >> "${BACKUP_PATH}/system/system-info.txt"
}

# Backup databases
backup_databases() {
    log "🗄️  Backing up databases..."
    
    mkdir -p "${BACKUP_PATH}/databases"
    
    # MySQL backup
    if [ "$BACKUP_MYSQL" = "true" ] && command -v mysqldump >/dev/null; then
        log "  → MySQL databases"
        local mysql_databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)" || true)
        
        if [ -n "$mysql_databases" ]; then
            for db in $mysql_databases; do
                if [ -n "$db" ]; then
                    log "    → Database: $db"
                    if mysqldump --single-transaction --quick "$db" 2>/dev/null | gzip > "${BACKUP_PATH}/databases/${db}.mysql.sql.gz"; then
                        log "      ✅ Success"
                    else
                        warn "      ❌ Failed to backup MySQL database: $db"
                    fi
                fi
            done
        else
            log "    → No MySQL databases found"
        fi
    else
        info "  → MySQL: skipped or not installed"
    fi
    
    # PostgreSQL backup
    if [ "$BACKUP_POSTGRES" = "true" ] && command -v pg_dump >/dev/null; then
        log "  → PostgreSQL databases"
        local pg_databases=$(sudo -u postgres psql -l -t 2>/dev/null | cut -d'|' -f1 | sed 's/ //g' | grep -v '^$' | grep -v template | grep -v postgres || true)
        
        if [ -n "$pg_databases" ]; then
            for db in $pg_databases; do
                if [ -n "$db" ]; then
                    log "    → Database: $db"
                    if sudo -u postgres pg_dump "$db" 2>/dev/null | gzip > "${BACKUP_PATH}/databases/${db}.pgsql.sql.gz"; then
                        log "      ✅ Success"
                    else
                        warn "      ❌ Failed to backup PostgreSQL database: $db"
                    fi
                fi
            done
        else
            log "    → No PostgreSQL databases found"
        fi
    else
        info "  → PostgreSQL: skipped or not installed"
    fi
}

# Backup web services
backup_web_services() {
    if [ "$BACKUP_WEB_DIRS" != "true" ]; then
        info "🌐 Web services backup skipped (config)"
        return 0
    fi
    
    log "🌐 Backing up web services..."
    
    mkdir -p "${BACKUP_PATH}/web"
    
    # Web directories
    local web_dirs=("/var/www" "/srv/www" "/home/*/www" "/home/*/public_html")
    local found_dirs=0
    
    for dir_pattern in "${web_dirs[@]}"; do
        for dir in $dir_pattern; do
            if [ -d "$dir" ]; then
                local dir_name=$(basename "$dir")
                log "  → Web directory: $dir"
                if tar -czf "${BACKUP_PATH}/web/${dir_name}.tar.gz" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null; then
                    log "      ✅ Success"
                    found_dirs=1
                else
                    warn "      ❌ Failed to backup web directory: $dir"
                fi
            fi
        done
    done
    
    if [ $found_dirs -eq 0 ]; then
        log "  → No web directories found"
    fi
    
    # Nginx configurations
    if [ -d "/etc/nginx" ]; then
        log "  → Nginx configurations"
        tar -czf "${BACKUP_PATH}/web/nginx-configs.tar.gz" -C / etc/nginx/ 2>/dev/null || warn "Failed to backup Nginx configs"
    fi
    
    # Apache configurations
    if [ -d "/etc/apache2" ]; then
        log "  → Apache configurations"
        tar -czf "${BACKUP_PATH}/web/apache-configs.tar.gz" -C / etc/apache2/ 2>/dev/null || warn "Failed to backup Apache configs"
    fi
}

# Create checksums for integrity verification
create_checksums() {
    log "🔐 Creating checksums for integrity verification..."
    cd "${BACKUP_PATH}"
    find . -type f -not -name "checksums.txt" -exec sha256sum {} \; > checksums.txt
}

# Verify backup integrity
verify_backup() {
    log "🔍 Verifying backup integrity..."
    cd "${BACKUP_PATH}"
    
    if sha256sum -c checksums.txt >/dev/null 2>&1; then
        log "✅ Backup integrity verified"
        return 0
    else
        warn "⚠️  Backup integrity check failed"
        return 1
    fi
}

# Create final archive
create_final_archive() {
    log "📦 Creating final archive..."
    
    cd "$BACKUP_DIR"
    
    # Create archive with compression level
    if tar -czf "${BACKUP_NAME}.tar.gz" --warning=no-file-changed "$BACKUP_NAME"/; then
        local final_size=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
        log "✓ Final archive created: ${BACKUP_NAME}.tar.gz (${final_size})"
    else
        error "Failed to create final archive"
    fi
    
    # Cleanup temporary directory
    rm -rf "$BACKUP_PATH"
}

# Cleanup old backups
cleanup_old_backups() {
    log "🧹 Cleaning up old backups (older than ${RETENTION_DAYS} days)..."
    
    local deleted_count=0
    for file in $(find "$BACKUP_DIR" -name "vps-backup-*.tar.gz" -mtime "+$RETENTION_DAYS"); do
        log "  → Removing: $(basename "$file")"
        rm -f "$file"
        ((deleted_count++))
    done
    
    if [ "$deleted_count" -gt 0 ]; then
        log "✓ Removed $deleted_count old backup(s)"
    else
        log "✓ No old backups to remove"
    fi
}

# Display summary
display_summary() {
    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    
    echo
    log "======= BACKUP SUMMARY ======="
    if [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✅ Backup completed successfully!"
        log "📁 File: $(basename "$backup_file")"
        log "💾 Size: $size"
        log "📅 Date: $(date)"
        log "💿 Disk space: $(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4 " available"}')"
    else
        error "Backup file was not created successfully"
    fi
    log "==============================="
}

# Main execution
main() {
    log "🚀 Starting VPS backup process..."
    log "Backup directory: $BACKUP_DIR"
    log "Retention days: $RETENTION_DAYS"
    
    check_prerequisites
    
    # Create backup directory
    mkdir -p "$BACKUP_PATH"
    
    backup_system_files
    backup_databases
    backup_web_services
    create_checksums
    verify_backup
    create_final_archive
    cleanup_old_backups
    display_summary
}

# Handle script interruption
trap 'error "Backup interrupted by user"' INT TERM

# Run main function
main "$@"