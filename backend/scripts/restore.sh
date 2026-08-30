#!/bin/bash

# ============================================================================
# Movex GO Database Restore Script
# ============================================================================
# Bu script PostgreSQL database ni backup fayldan restore qiladi
# Ishlatish: ./restore.sh <backup_file>
# Example: ./restore.sh database/backups/backup_full_20241117_120000.sql.gz
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables from .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source <(grep -v '^#' "$PROJECT_ROOT/.env" | grep -v '^$' | sed 's/=\s*$/=/')
    set +a
fi

# Database configuration
DB_NAME="${POSTGRES_DB:-movex_go}"
DB_USER="${POSTGRES_USER:-shohruxbek}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
show_usage() {
    echo "Usage: $0 <backup_file>"
    echo ""
    echo "Example:"
    echo "  $0 database/backups/backup_full_20241117_120000.sql.gz"
    echo "  $0 database/backups/backup_full_20241117_120000.sql"
    echo ""
    echo "Options:"
    echo "  --help        Show this help message"
}

# Validate backup file
validate_backup_file() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check file extension
    if [[ ! "$backup_file" =~ \.(sql|sql\.gz)$ ]]; then
        log_error "Invalid backup file format. Expected .sql or .sql.gz"
        return 1
    fi
    
    return 0
}

# Confirm restore
confirm_restore() {
    local backup_file=$1
    
    log_warning "⚠️  WARNING: This will REPLACE all data in database '$DB_NAME'"
    log_warning "⚠️  Current data will be LOST!"
    echo ""
    log_info "Backup file: $backup_file"
    log_info "Database: $DB_NAME"
    log_info "Host: $DB_HOST:$DB_PORT"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
}

# Perform restore
perform_restore() {
    local backup_file=$1
    
    log_info "Starting database restore..."
    
    # Set password for psql
    export PGPASSWORD="$DB_PASSWORD"
    
    # Check if file is compressed
    if [[ "$backup_file" =~ \.gz$ ]]; then
        log_info "Decompressing and restoring..."
        if gunzip -c "$backup_file" | psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d $DB_NAME 2>/dev/null; then
            log_success "Database restored successfully!"
            return 0
        else
            log_error "Restore failed!"
            return 1
        fi
    else
        log_info "Restoring from uncompressed file..."
        if psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d $DB_NAME < "$backup_file" 2>/dev/null; then
            log_success "Database restored successfully!"
            return 0
        else
            log_error "Restore failed!"
            return 1
        fi
    fi
    
    unset PGPASSWORD
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Check arguments
    if [ $# -eq 0 ]; then
        log_error "No backup file specified"
        echo ""
        show_usage
        exit 1
    fi
    
    if [ "$1" == "--help" ]; then
        show_usage
        exit 0
    fi
    
    local backup_file=$1
    
    # Validate backup file
    if ! validate_backup_file "$backup_file"; then
        exit 1
    fi
    
    # Confirm restore
    confirm_restore "$backup_file"
    
    # Perform restore
    if perform_restore "$backup_file"; then
        exit 0
    else
        exit 1
    fi
}

main "$@"

