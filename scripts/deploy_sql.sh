#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying SQL to vinabike-staging...${NC}\n"

# Default to core_schema_compat.sql, but allow override
SQL_FILE="${1:-supabase/sql/core_schema_compat.sql}"

if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}❌ Error: File not found: $SQL_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}📄 File: $SQL_FILE${NC}"
echo -e "${BLUE}📊 Size: $(wc -l < "$SQL_FILE") lines${NC}\n"

# Database connection details
DB_HOST="db.kyvgmapifacpzuyreasy.supabase.co"
DB_PORT="5432"
DB_NAME="postgres"
DB_USER="postgres"
DB_PASSWORD="Vinabike2901"

# Deploy SQL file directly using psql
echo -e "${BLUE}📤 Deploying SQL file to vinabike-staging...${NC}\n"
echo -e "${YELLOW}⏳ This may take a few minutes for 17,000+ lines...${NC}\n"

if PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -f "$SQL_FILE" \
    -v ON_ERROR_STOP=1 \
    --quiet; then
    
    echo -e "\n${GREEN}✅ Deployment successful!${NC}"
    echo -e "${GREEN}🎉 SQL deployed to vinabike-staging${NC}\n"
else
    echo -e "\n${RED}❌ Deployment failed!${NC}"
    echo -e "${RED}Check the error messages above for details.${NC}\n"
    exit 1
fi

echo -e "${BLUE}✨ Done! Your SQL is now live on vinabike-staging.${NC}"
