#!/bin/bash
# =============================================================================
# teardown.sh — Ferma e pulisce l'ambiente del progetto D5
# Uso: bash teardown.sh          # ferma i container, mantiene i volumi
#      bash teardown.sh --full   # ferma tutto e cancella anche i volumi
# =============================================================================

echo "=================================================="
echo " Teardown progetto D5 — Ricerca anagrafica + audit"
echo "=================================================="

FULL=false
if [ "$1" == "--full" ]; then
    FULL=true
fi

# --- 1. Verifica che Docker sia attivo ---
if ! docker info &> /dev/null; then
    echo "ERRORE: Docker non è in esecuzione."
    exit 1
fi

# --- 2. Mostra stato attuale ---
echo ""
echo "Stato attuale dei container:"
docker compose ps

# --- 3. Conferma ---
echo ""
if [ "$FULL" = true ]; then
    echo "ATTENZIONE: --full cancellerà tutti i volumi e i dati del database."
fi
read -p "Procedere con il teardown? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Teardown annullato."
    exit 0
fi

# --- 4. Ferma e rimuovi container ---
echo ""
echo "[1/3] Fermo i container..."
docker compose down
echo "      Container fermati e rimossi: OK"

# --- 5. Rimuovi volumi se --full ---
if [ "$FULL" = true ]; then
    echo ""
    echo "[2/3] Rimozione volumi..."
    docker compose down -v
    echo "      Volumi rimossi: OK"
else
    echo ""
    echo "[2/3] Volumi mantenuti (usa --full per cancellarli)."
fi

# --- 6. Rimuovi immagini buildate ---
echo ""
read -p "[3/3] Rimuovere anche le immagini buildate (api, audit-log)? [y/N] " REMOVE_IMAGES
if [[ "$REMOVE_IMAGES" =~ ^[Yy]$ ]]; then
    docker rmi d5-api d5-audit-log 2>/dev/null && echo "      Immagini rimosse: OK" || echo "      Nessuna immagine da rimuovere."
fi

# --- 7. Riepilogo ---
echo ""
echo "=================================================="
echo " Teardown completato."
echo ""
if [ "$FULL" = true ]; then
    echo " Rimosso: container, reti, volumi."
    echo " Per ripartire da zero: bash setup.sh"
else
    echo " Rimosso: container, reti."
    echo " Volumi mantenuti — i dati sono ancora presenti."
    echo " Per riavviare senza rebuild: docker compose up -d"
    echo " Per ripartire da zero:       bash teardown.sh --full && bash setup.sh"
fi
echo "=================================================="
