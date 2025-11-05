#!/bin/bash

#
# Database Backup Script
# Резервное копирование только баз данных
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
DB_BACKUP_DIR="${DB_BACKUP_DIR:-${BACKUP_DIR}/databases}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="${DB_LOG_FILE:-/var/log/db-backup.log}"
BACKUP_MYSQL="${BACKUP_MYSQL:-true}"
BACKUP_POSTGRES="${BACKUP_POSTGRES:-true}"

# Variables
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H-%M-%S)
BACKUP_PATH="${DB_BACKUP_DIR}/${DATE}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
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
    mkdir -p "$DB_BACKUP_DIR" || error "Failed to create backup directory"
    
    if [ "$BACKUP_MYSQL" = "true" ] && ! command -v mysqldump >/dev/null; then
        warn "MySQL backup enabled but mysqldump not found"
    fi
    
    if [ "$BACKUP_POSTGRES" = "true" ] && ! command -v pg_dump >/dev/null; then
        warn "PostgreSQL backup enabled but pg_dump not found"
    fi
}

# Backup MySQL databases
backup_mysql() {
    if [ "$BACKUP_MYSQL" != "true" ]; then
        info "MySQL backup skipped (config)"
        return 0
    fi
    
    if ! command -v mysqldump >/dev/null; then
        warn "MySQL: mysqldump not available"
        return 0
    fi
    
    log "🗄️  Backing up MySQL databases..."
    
    local mysql_databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)" || true)
    local success_count=0
    local total_count=0
    
    if [ -n "$mysql_databases" ]; then
        for db in $mysql_databases; do
            if [ -n "$db" ]; then
                ((total_count++))
                log "  → Database: $db"
                local backup_file="${BACKUP_PATH}/mysql/${db}.sql.gz"
                mkdir -p "$(dirname "$backup_file")"
                
                if mysqldump --single-transaction --quick "$db" 2>/dev/null | gzip > "$backup_file"; then
                    log "      ✅ Success ($(du -h "$backup_file" | cut -f1))"
                    ((success_count++))
                else
                    warn "      ❌ Failed to backup: $db"
                    rm -f "$backup_file"
                fi
            fi
        done
        log "✓ MySQL: $success_count/$total_count databases backed up successfully"
    else
        log "  → No MySQL databases found"
    fi
}

# Backup PostgreSQL databases
backup_postgresql() {
    if [ "$BACKUP_POSTGRES" != "true" ]; then
        info "PostgreSQL backup skipped (config)"
        return 0
    fi
    
    if ! command -v pg_dump >/dev/null; then
        warn "PostgreSQL: pg_dump not available"
        return 0
    fi
    
    log "🗄️  Backing up PostgreSQL databases..."
    
    local pg_databases=$(sudo -u postgres psql -l -t 2>/dev/null | cut -d'|' -f1 | sed 's/ //g' | grep -v '^$' | grep -v template | grep -v postgres || true)
    local success_count=0
    local total_count=0
    
    if [ -n "$pg_databases" ]; then
        for db in $pg_databases; do
            if [ -n "$db" ]; then
                ((total_count++))
                log "  → Database: $db"
                local backup_file="${BACKUP_PATH}/postgresql/${db}.sql.gz"
                mkdir -p "$(dirname "$backup_file")"
                
                if sudo -u postgres pg_dump "$db" 2>/dev/null | gzip > "$backup_file"; then
                    log "      ✅ Success ($(du -h "$backup_file" | cut -f1))"
                    ((success_count++))
                else
                    warn "      ❌ Failed to backup: $db"
                    rm -f "$backup_file"
                fi
            fi
        done
        log "✓ PostgreSQL: $success_count/$total_count databases backed up successfully"
    else
        log "  → No PostgreSQL databases found"
    fi
}

# Create backup info file
create_backup_info() {
    local info_file="${BACKUP_PATH}/backup-info.txt"
    
    echo "=== Database Backup Information ===" > "$info_file"
    echo "Backup Date: $(date)" >> "$info_file"
    echo "Backup Time: $TIMESTAMP" >> "$info_file"
    echo "Backup Directory: $BACKUP_PATH" >> "$info_file"
    echo "Retention Days: $RETENTION_DAYS" >> "$info_file"
    echo "MySQL Backup: $BACKUP_MYSQL" >> "$info_file"
    echo "PostgreSQL Backup: $BACKUP_POSTGRES" >> "$info_file"
    echo "===================================" >> "$info_file"
}

# Cleanup old backups
cleanup_old_backups() {
    log "🧹 Cleaning up old database backups (older than ${RETENTION_DAYS} days)..."
    
    local deleted_count=0
    for dir in $(find "$DB_BACKUP_DIR" -type d -name "202*" -mtime "+$RETENTION_DAYS"); do
        if [ -d "$dir" ]; then
            log "  → Removing: $(basename "$dir")"
            rm -rf "$dir"
            ((deleted_count++))
        fi
    done
    
    if [ "$deleted_count" -gt 0 ]; then
        log "✓ Removed $deleted_count old database backup(s)"
    else
        log "✓ No old database backups to remove"
    fi
}

# Display summary
display_summary() {
    echo
    log "======= DATABASE BACKUP SUMMARY ======="
    log "✅ Database backup completed!"
    log "📁 Location: $BACKUP_PATH"
    log "📅 Date: $DATE"
    log "🕐 Time: $TIMESTAMP"
    log "💿 Disk usage: $(du -sh "$BACKUP_PATH" | cut -f1)"
    log "========================================"
}

# Main execution
main() {
    log "🚀 Starting database backup process..."
    
    check_prerequisites
    mkdir -p "$BACKUP_PATH"
    
    backup_mysql
    backup_postgresql
    create_backup_info
    cleanup_old_backups
    display_summary
}

# Handle script interruption
trap 'error "Database backup interrupted by user"' INT TERM

# Run main function
main "$@"