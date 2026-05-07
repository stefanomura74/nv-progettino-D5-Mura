#!/bin/bash
# =============================================================================
# setup.sh — Avvia l'ambiente completo del progetto D5
# Uso: bash setup.sh
# =============================================================================

set -e  # interrompe lo script al primo errore

echo "=================================================="
echo " Setup progetto D5 — Ricerca anagrafica + audit"
echo "=================================================="

# --- 1. Verifica prerequisiti ---
echo ""
echo "[1/5] Verifica prerequisiti..."

if ! command -v docker &> /dev/null; then
    echo "ERRORE: Docker non trovato. Installare Docker Engine prima di procedere."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Docker non è avviato. Avvio in corso..."
    sudo service docker start
    sleep 3
fi

echo "      Docker: OK ($(docker --version))"
echo "      Docker Compose: OK ($(docker compose version))"

# --- 2. Verifica file necessari ---
echo ""
echo "[2/5] Verifica struttura progetto..."

REQUIRED_FILES=(
    "docker-compose.yml"
    "frontend/index.html"
    "api/Dockerfile"
    "api/requirements.txt"
    "api/main.py"
    "audit-log/Dockerfile"
    "audit-log/consumer.py"
    "db/init.sql"
    "db/famiglie.csv"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "ERRORE: File mancante: $f"
        exit 1
    fi
done

echo "      Tutti i file presenti: OK"

# --- 3. Build e avvio container ---
echo ""
echo "[3/5] Build e avvio container..."
docker compose up -d --build

# --- 4. Attendi che PostgreSQL sia pronto ---
echo ""
echo "[4/5] Attendo che il database sia pronto..."

MAX_RETRIES=15
COUNT=0
until docker compose exec -T db psql -U user -d dataset -c "SELECT 1;" &> /dev/null; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "ERRORE: Database non raggiungibile dopo $MAX_RETRIES tentativi."
        echo "Controlla i log con: docker compose logs db"
        exit 1
    fi
    echo "      Attendo... ($COUNT/$MAX_RETRIES)"
    sleep 3
done

echo "      Database: OK"

# --- 5. Verifica finale ---
echo ""
echo "[5/5] Verifica funzionamento..."

# Conta le righe importate
ROW_COUNT=$(docker compose exec -T db psql -U user -d dataset -t -c "SELECT count(*) FROM famiglie;" | tr -d ' ')
echo "      Righe importate nel DB: $ROW_COUNT"

# Verifica audit-log in ascolto
sleep 2
AUDIT_LOG=$(docker compose logs audit-log 2>&1)
if echo "$AUDIT_LOG" | grep -q "Consumer avviato"; then
    echo "      Audit log consumer: OK"
else
    echo "      ATTENZIONE: audit-log potrebbe non essere pronto. Controlla con: docker compose logs audit-log"
fi

# Stato container
echo ""
echo "Stato container:"
docker compose ps

echo ""
echo "=================================================="
echo " Setup completato!"
echo ""
echo " Frontend:  http://localhost:8080"
echo " API:       http://localhost:3000/search?nome=chiara"
echo " Swagger:   http://localhost:3000/apidocs"
echo "=================================================="
