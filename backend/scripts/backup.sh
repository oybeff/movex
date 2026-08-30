#!/bin/bash

# ============================================================================
# Movex GO Database Backup Script
# ============================================================================
# Bu script PostgreSQL database ni backup qiladi va eski backuplarni o'chiradi
# Ishlatish: ./backup.sh [OPTIONS]
# Options:
#   --full      : Full backup (default)
#   --schema    : Schema only backup
#   --data      : Data only backup
#   --compress  : Compress backup (default: yes)
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

# Backup configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/database/backups}"
# Ulanish sozlamalari DATABASE_URL dan olinadi — ilova aynan shundan
# foydalanadi, ya'ni ikkinchi manba bo'lmaydi.
#
# Ilgari bu yerda faqat POSTGRES_* o'zgaruvchilari o'qilardi. Ular .env da
# yo'q, shuning uchun skript standart qiymatlarga tushardi (foydalanuvchi
# "shohruxbek" — boshqa mashinadan qolgan) va zaxira nusxa har safar
# xato bilan tugardi.
#
# Format: postgresql://user[:password]@host[:port]/dbname
parse_database_url() {
    local url="${DATABASE_URL:-}"
    [ -z "$url" ] && return 1

    local rest="${url#*://}"
    local creds="" hostpart=""
    if [[ "$rest" == *"@"* ]]; then
        creds="${rest%%@*}"
        hostpart="${rest#*@}"
    else
        hostpart="$rest"
    fi

    if [ -n "$creds" ]; then
        URL_USER="${creds%%:*}"
        if [[ "$creds" == *":"* ]]; then
            URL_PASSWORD="${creds#*:}"
        fi
    fi

    URL_DB="${hostpart#*/}"
    URL_DB="${URL_DB%%\?*}"

    local hostport="${hostpart%%/*}"
    URL_HOST="${hostport%%:*}"
    if [[ "$hostport" == *":"* ]]; then
        URL_PORT="${hostport#*:}"
    fi
    return 0
}

URL_USER=""; URL_PASSWORD=""; URL_HOST=""; URL_PORT=""; URL_DB=""
parse_database_url || true

DB_NAME="${POSTGRES_DB:-${URL_DB:-movex_go}}"
DB_USER="${POSTGRES_USER:-${URL_USER:-$(whoami)}}"
DB_PASSWORD="${POSTGRES_PASSWORD:-$URL_PASSWORD}"
DB_HOST="${POSTGRES_HOST:-${URL_HOST:-localhost}}"
DB_PORT="${POSTGRES_PORT:-${URL_PORT:-5432}}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Backup options
BACKUP_TYPE="full"
COMPRESS=true

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

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                BACKUP_TYPE="full"
                shift
                ;;
            --schema)
                BACKUP_TYPE="schema"
                shift
                ;;
            --data)
                BACKUP_TYPE="data"
                shift
                ;;
            --no-compress)
                COMPRESS=false
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --full        Full backup (default)"
                echo "  --schema      Schema only backup"
                echo "  --data        Data only backup"
                echo "  --no-compress Don't compress backup"
                echo "  --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
}

# Perform backup
perform_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${BACKUP_TYPE}_${timestamp}"
    local backup_file="$BACKUP_DIR/${backup_name}.sql"

    log_info "Starting database backup..."
    log_info "Database: $DB_NAME"
    log_info "User: $DB_USER"
    log_info "Host: $DB_HOST:$DB_PORT"
    log_info "Type: $BACKUP_TYPE"

    # Set password for pg_dump
    export PGPASSWORD="$DB_PASSWORD"

    # Build pg_dump command
    local pg_dump_cmd="pg_dump -U $DB_USER -h $DB_HOST -p $DB_PORT"

    case $BACKUP_TYPE in
        schema)
            pg_dump_cmd="$pg_dump_cmd --schema-only"
            ;;
        data)
            pg_dump_cmd="$pg_dump_cmd --data-only"
            ;;
        full)
            pg_dump_cmd="$pg_dump_cmd --clean --if-exists"
            ;;
    esac

    # Execute backup
    if $pg_dump_cmd $DB_NAME > "$backup_file" 2>/dev/null; then
        # Compress if needed
        if $COMPRESS; then
            log_info "Compressing backup..."
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi

        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Backup created successfully!"
        log_info "File: $backup_file"
        log_info "Size: $backup_size"

        # Create metadata file
        create_metadata "$backup_file" "$backup_size"

        return 0
    else
        log_error "Backup failed!"
        log_error "Please check database connection and permissions"
        return 1
    fi

    unset PGPASSWORD
}

# Create metadata file
create_metadata() {
    local backup_file=$1
    local backup_size=$2
    local metadata_file="${backup_file}.meta"

    cat > "$metadata_file" <<EOF
{
    "backup_file": "$(basename $backup_file)",
    "backup_type": "$BACKUP_TYPE",
    "database": "$DB_NAME",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "size": "$backup_size",
    "compressed": $COMPRESS,
    "host": "$DB_HOST",
    "port": "$DB_PORT"
}
EOF
}

# Clean old backups
clean_old_backups() {
    log_info "Cleaning old backups (older than $RETENTION_DAYS days)..."

    local deleted_count=0
    while IFS= read -r file; do
        rm -f "$file" "${file}.meta"
        ((deleted_count++))
    done < <(find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -o -name "backup_*.sql" -mtime +$RETENTION_DAYS)

    if [ $deleted_count -gt 0 ]; then
        log_success "Deleted $deleted_count old backup(s)"
    else
        log_info "No old backups to delete"
    fi
}

# List current backups
list_backups() {
    log_info "Current backups:"
    echo ""

    if ls "$BACKUP_DIR"/backup_*.sql* 1> /dev/null 2>&1; then
        printf "%-40s %-10s %-20s\n" "Filename" "Size" "Date"
        printf "%-40s %-10s %-20s\n" "--------" "----" "----"

        for file in "$BACKUP_DIR"/backup_*.sql*; do
            if [[ ! "$file" =~ \.meta$ ]]; then
                local filename=$(basename "$file")
                local size=$(du -h "$file" | cut -f1)
                local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
                printf "%-40s %-10s %-20s\n" "$filename" "$size" "$date"
            fi
        done
    else
        log_warning "No backups found"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"
    create_backup_dir

    if perform_backup; then
        clean_old_backups
        echo ""
        list_backups
        exit 0
    else
        exit 1
    fi
}

main "$@"

