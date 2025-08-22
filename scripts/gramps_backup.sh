#!/bin/bash

# Define paths
DB_PATH="./share/grampsdb/sqlite.db"
BACKUP_DIR="./share/backups"
BACKUP_FILE="database_backup_$(date +%Y%m%d%H%M%S).sqlite" # Unique filename with timestamp

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Perform the SQLite backup
sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/$BACKUP_FILE'"

# Navigate to the Git repository
cd "$BACKUP_DIR"

# Add the backup file to Git
git add "$BACKUP_FILE"
