#!/bin/bash

#
# Backup Integrity Check Script
# Verifies backup integrity and tests restoration capability
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
LOG_FILE="${LOG_FILE:-/var/log/vps-backup.log}"
ENABLE_INTEGRITY_CHECK="${ENABLE_INTEGRITY_CHECK:-true}"

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

# Check if integrity checking is enabled
check_enabled() {
    if [ "$ENABLE_INTEGRITY_CHECK" != "true" ]; then
        info "Integrity checking is disabled in configuration"
        exit 0
    fi
}

# Verify archive integrity
check_archive() {
    local archive_path=$1
    log "🔍 Verifying archive: $archive_path"
    
    if [ ! -f "$archive_path" ]; then
        error "Archive file not found: $archive_path"
    fi
    
    if [[ $archive_path == *.tar.gz ]]; then
        # Test archive structure
        if ! tar -tzf "$archive_path" &>/dev/null; then
            error "Archive is corrupted or invalid: $archive_path"
        else
            log "  ✅ Archive structure is valid"
        fi
        
        # Test extraction to temporary directory
        local temp_dir=$(mktemp -d)
        log "  → Testing extraction..."
        
        if tar -xzf "$archive_path" -C "$temp_dir" --strip-components=1 2>/dev/null; then
            local extracted_size=$(du -sh "$temp_dir" | cut -f1)
            log "  ✅ Extraction successful ($extracted_size)"
            
            # Check for important files
            if [ -f "$temp_dir/checksums.txt" ]; then
                log "  ✅ Checksum file found"
                
                # Verify checksums
                cd "$temp_dir"
                if sha256sum -c checksums.txt --quiet 2>/dev/null; then
                    log "  ✅ All checksums verified"
                else
                    warn "  ⚠️  Some checksums failed verification"
                fi
                cd - >/dev/null
            else
                warn "  ⚠️  No checksum file found in archive"
            fi
            
        else
            error "Failed to extract archive: $archive_path"
        fi
        
        # Cleanup
        rm -rf "$temp_dir"
        return 0
    else
        warn "  ⚠️  Unsupported archive format: $archive_path"
        return 1
    fi
}

# Verify MySQL dump integrity
verify_mysql_dump() {
    local dump_file=$1
    log "🔍 Verifying MySQL dump: $(basename "$dump_file")"
    
    if [ ! -f "$dump_file" ]; then
        warn "  ⚠️  Dump file not found: $dump_file"
        return 1
    fi
    
    # Check if file is compressed
    local test_file="$dump_file"
    if [[ "$dump_file" == *.gz ]]; then
        # Test gzip integrity
        if gzip -t "$dump_file" 2>/dev/null; then
            log "  ✅ Gzip compression is valid"
            # Create temporary decompressed file
            test_file=$(mktemp)
            zcat "$dump_file" > "$test_file"
        else
            error "Gzip compression is corrupted: $dump_file"
        fi
    fi
    
    # Basic SQL syntax check
    if head -n 100 "$test_file" | grep -q "CREATE TABLE\|INSERT INTO"; then
        log "  ✅ SQL dump structure appears valid"
    else
        warn "  ⚠️  SQL dump structure may be invalid"
    fi
    
    # Test with MySQL (if available and configured)
    if command -v mysql >/dev/null && [ -n "$MYSQL_USER" ]; then
        local test_db="test_integrity_$$"
        log "  → Testing database restoration..."
        
        if mysql -e "CREATE DATABASE $test_db;" 2>/dev/null; then
            if mysql "$test_db" < "$test_file" 2>/dev/null; then
                log "  ✅ Database restoration test successful"
                # Verify we have tables
                local table_count=$(mysql -e "USE $test_db; SHOW TABLES;" 2>/dev/null | wc -l)
                log "  → Found $table_count tables in test database"
            else
                warn "  ⚠️  Database restoration test failed"
            fi
            # Cleanup test database
            mysql -e "DROP DATABASE $test_db;" 2>/dev/null
        else
            info "  → Skipping database restoration test (no MySQL access)"
        fi
    else
        info "  → Skipping database restoration test (MySQL not configured)"
    fi
    
    # Cleanup temporary file if created
    if [[ "$dump_file" == *.gz ]] && [ -f "$test_file" ]; then
        rm -f "$test_file"
    fi
}

# Verify PostgreSQL dump integrity
verify_postgresql_dump() {
    local dump_file=$1
    log "🔍 Verifying PostgreSQL dump: $(basename "$dump_file")"
    
    if [ ! -f "$dump_file" ]; then
        warn "  ⚠️  Dump file not found: $dump_file"
        return 1
    fi
    
    # Check if file is compressed
    if [[ "$dump_file" == *.gz ]]; then
        # Test gzip integrity
        if gzip -t "$dump_file" 2>/dev/null; then
            log "  ✅ Gzip compression is valid"
        else
            error "Gzip compression is corrupted: $dump_file"
        fi
    fi
    
    # Basic check for PostgreSQL dump format
    if zcat "$dump_file" 2>/dev/null | head -n 50 | grep -q "PostgreSQL database dump"; then
        log "  ✅ PostgreSQL dump format detected"
    else
        warn "  ⚠️  May not be a valid PostgreSQL dump"
    fi
}

# Check latest backup
check_latest_backup() {
    local latest_backup=$(find "$BACKUP_DIR" -name "vps-backup-*.tar.gz" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_backup" ]; then
        error "No backup files found in $BACKUP_DIR"
    fi
    
    log "📦 Checking latest backup: $(basename "$latest_backup")"
    check_archive "$latest_backup"
    
    # Extract and check internal structure
    local temp_dir=$(mktemp -d)
    tar -xzf "$latest_backup" -C "$temp_dir"
    
    # Check database dumps if they exist
    if [ -d "$temp_dir/databases" ]; then
        log "🗄️  Verifying database dumps..."
        
        # MySQL dumps
        for mysql_dump in "$temp_dir"/databases/*.mysql.sql.gz; do
            if [ -f "$mysql_dump" ]; then
                verify_mysql_dump "$mysql_dump"
            fi
        done
        
        # PostgreSQL dumps
        for pg_dump in "$temp_dir"/databases/*.pgsql.sql.gz; do
            if [ -f "$pg_dump" ]; then
                verify_postgresql_dump "$pg_dump"
            fi
        done
    fi
    
    # Check system files structure
    if [ -d "$temp_dir/system" ]; then
        log "📁 Verifying system backup structure..."
        local system_files=("etc.tar.gz" "home.tar.gz" "root.tar.gz")
        for sys_file in "${system_files[@]}"; do
            if [ -f "$temp_dir/system/$sys_file" ]; then
                log "  ✅ Found: $sys_file"
            fi
        done
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Check specific backup file
check_specific_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi
    
    log "🔍 Checking specific backup: $backup_file"
    check_archive "$backup_file"
}

# Check database backups
check_database_backups() {
    local db_backup_dir="${DB_BACKUP_DIR:-$BACKUP_DIR/databases}"
    
    if [ ! -d "$db_backup_dir" ]; then
        warn "Database backup directory not found: $db_backup_dir"
        return 0
    fi
    
    log "🗄️  Checking database backups in: $db_backup_dir"
    
    local latest_db_dir=$(find "$db_backup_dir" -type d -name "202*" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_db_dir" ]; then
        warn "No database backup directories found"
        return 0
    fi
    
    log "→ Latest database backup: $(basename "$latest_db_dir")"
    
    # Check MySQL backups
    if [ -d "$latest_db_dir/mysql" ]; then
        log "→ MySQL backups:"
        for db_file in "$latest_db_dir/mysql"/*.sql.gz; do
            if [ -f "$db_file" ]; then
                verify_mysql_dump "$db_file"
            fi
        done
    fi
    
    # Check PostgreSQL backups
    if [ -d "$latest_db_dir/postgresql" ]; then
        log "→ PostgreSQL backups:"
        for db_file in "$latest_db_dir/postgresql"/*.sql.gz; do
            if [ -f "$db_file" ]; then
                verify_postgresql_dump "$db_file"
            fi
        done
    fi
}

# Display summary
display_summary() {
    echo
    log "======= INTEGRITY CHECK SUMMARY ======="
    log "✅ All integrity checks completed"
    log "📊 Backup directory: $BACKUP_DIR"
    log "🔐 Integrity checking: $ENABLE_INTEGRITY_CHECK"
    log "📝 Log file: $LOG_FILE"
    log "========================================"
}

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -f, --file FILE     Check specific backup file"
    echo "  -d, --databases     Check only database backups"
    echo "  -l, --latest        Check latest backup (default)"
    echo
    echo "Examples:"
    echo "  $0 --latest         Check latest backup"
    echo "  $0 --file /backup/vps-backup-2024-01-15.tar.gz"
    echo "  $0 --databases      Check database backups only"
}

# Main execution
main() {
    local check_latest=true
    local check_databases=false
    local specific_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--file)
                specific_file="$2"
                check_latest=false
                shift 2
                ;;
            -d|--databases)
                check_databases=true
                check_latest=false
                shift
                ;;
            -l|--latest)
                check_latest=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    log "🔍 Starting backup integrity check..."
    
    check_enabled
    
    if [ -n "$specific_file" ]; then
        check_specific_backup "$specific_file"
    elif [ "$check_databases" = true ]; then
        check_database_backups
    elif [ "$check_latest" = true ]; then
        check_latest_backup
    fi
    
    display_summary
}

# Handle script interruption
trap 'error "Integrity check interrupted by user"' INT TERM

# Run main function
main "$@"