# Microservizi con Docker Compose — Ricerca anagrafica con audit log

**Autore:** Stefano Mura  
**Codice variante:** D5  
**Repo:** *(da aggiungere)*

---

## 1. Obiettivo

Il progetto implementa un'applicazione web a microservizi per la ricerca di dati anagrafici (persone) caricati da un file CSV in un database PostgreSQL. L'architettura prevede un reverse proxy Nginx, un'API REST Flask, due database PostgreSQL separati (dati e audit), una cache Redis e un servizio di audit log asincrono. L'obiettivo didattico è dimostrare l'isolamento di rete tra container, la persistenza dei dati tramite volumi Docker, e un pattern di audit non bloccante basato su coda Redis.

---

## 2. Architettura

L'applicazione è composta da sei container orchestrati con Docker Compose, distribuiti su due reti virtuali separate.

```
Internet (browser)
        │
        ▼
┌─────────────────┐
│  frontend/nginx │  :8080  ← unico punto esposto
│  rete: public   │
└────────┬────────┘
         │ proxy /search → :8000
         ▼
┌─────────────────┐
│   api (Flask)   │  rete: public + private (la porta 3000 è esposta per comodità   
|                 |         di sviluppo/test, in produzione andrebbe rimossa)
└──┬──────────┬───┘
   │          │ thread daemon → RPUSH
   ▼          ▼
┌──────┐   ┌───────────────┐
│  db  │   │  cache/Redis  │
│(PG)  │   │  audit_queue  │
└──────┘   └───────┬───────┘
                   │ BLPOP
                   ▼
          ┌─────────────────┐
          │   audit-log     │  rete: private
          │  (consumer.py)  │
          └────────┬────────┘
                   │
          ┌────────┴────────┐
          ▼                 ▼
      ┌───────┐      ┌────────────┐
      │ audit │      │ audit.log  │
      │ (PG)  │      │ (volume)   │
      └───────┘      └────────────┘
```

**Reti:**
- `public` — frontend ↔ api
- `private` — api ↔ db ↔ cache ↔ audit ↔ audit-log

**Volumi:**
- `db_data` — dati anagrafici PostgreSQL
- `audit_data` — database audit PostgreSQL  
- `audit_file` — file append-only `/audit-data/audit.log`
- `redis_data` — persistenza coda Redis

**Pattern di audit:** l'API scrive l'evento su una lista Redis (`RPUSH audit_queue`) in un thread daemon separato, senza attendere la risposta. Il consumer `audit-log` legge dalla coda con `BLPOP` (bloccante con timeout) e scrive sia su PostgreSQL che su file. Se `audit-log` è temporaneamente spento, gli eventi si accumulano in Redis e vengono consumati al riavvio — nessun evento viene perso.

---

## 3. Prerequisiti

| Componente | Versione testata |
|---|---|
| Windows | 10.0.26200 |
| WSL2 | 2.6.3.0 |
| Ubuntu (WSL) | 24.04.4 LTS (Noble) |
| Docker Engine | 29.4.1 |
| Docker Compose | v5.1.3 |

**Nota:** il progetto gira interamente dentro WSL2. Non è necessario Docker Desktop. Se si usa Symantec Endpoint Protection, verificare che il traffico TCP dal virtual adapter WSL non sia bloccato (impostare "Consenti traffico IP" nelle impostazioni firewall di Symantec).

---

## 4. Come riprodurre passo-passo

```bash
# 1. Clonare il repository
git clone https://github.com/.../nv-progettino-D5-mura.git
cd nv-progettino-D5-mura

# 2. Verificare che Docker sia avviato
sudo service docker start
# Output atteso: * Starting Docker: docker  [ OK ]

# 3. Verificare la struttura del progetto
ls
# Output atteso: docker-compose.yml  frontend/  api/  audit-log/  db/

# 4. Verificare che il CSV sia presente
ls db/
# Output atteso: famiglie.csv  init.sql

# 5. Costruire le immagini e avviare tutti i container
docker compose up -d --build
# Output atteso: 6 container con stato "Started"

# 6. Verificare che tutti i container siano Running
docker compose ps
# Output atteso: tutti i servizi con Status "running"

# 7. Attendere ~10 secondi che PostgreSQL sia pronto, poi verificare
#    che il CSV sia stato importato correttamente
docker compose exec db psql -U user -d dataset -c "SELECT count(*) FROM famiglie;"
# Output atteso: un numero > 0 (numero di righe nel CSV)

# 8. Verificare che il consumer audit sia in ascolto
docker compose logs audit-log
# Output atteso: [AUDIT] Database pronto
#               [AUDIT] Consumer avviato, in ascolto su audit_queue...
```

---

## 5. Verifica del funzionamento

### 5.1 Ricerca dal browser

Aprire `http://localhost:8080` — si apre l'interfaccia di ricerca. Inserire un nome parziale (es. "simon") e premere Search. La tabella mostra Nome, Anno nascita, Cittadinanza, Sesso:

![alt text](screenshots/image-3.png)

![alt text](screenshots/image-1.png)

Il log si popola con la ricerca:
```bash
$ docker compose exec audit-log cat /audit-data/audit.log
```
![alt text](screenshots/image-5.png)

Effettuando una successiva ricerca:

![alt text](screenshots/image-2.png)

Il log aggiunge la nuova riga:

```bash
$ docker compose exec audit-log cat /audit-data/audit.log
```
![alt text](screenshots/image-4.png)

Una volta controllato il funzionamento, prima di mettere i produzione si può fare un hash del parametro (o dei parametri) di ricerca, se contengono dati riservati (in questo caso il nome) che non sono rilevanti per il trattamento:


```bash
def audit_event(endpoint, params, client_ip):
    def _push():
        try:
            event = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "endpoint": endpoint,
                #"params": params
                # hashing parameters for privacy before sending to Redis
                "params": {k: (hash(v) if isinstance(v, str) else v) for k, v in params.items()},
                "client_ip": client_ip
            }
            r = get_redis()
            r.rpush("audit_queue", json.dumps(event))
        except Exception as e:
            print(f"[AUDIT] Errore push Redis: {e}")
    
    t = threading.Thread(target=_push, daemon=True)
    t.start()

```

Il log verrà quindi anonimizzato.

![alt text](screenshots/image6.png)


### 5.2 Ricerca via curl

```bash
curl "http://localhost:3000/search?nome=chiara"
# Output atteso: array JSON con i risultati

curl "http://localhost:3000/search?nome=xyz_inesistente"
# Output atteso: {"error": "Nessun risultato trovato"} con HTTP 404

curl "http://localhost:3000/search"
# Output atteso: {"error": "Parametro nome obbligatorio"} con HTTP 400
```

### 5.3 Documentazione API (Swagger)

Aprire `http://localhost:3000/apidocs` — interfaccia Swagger con la route `/search` documentata e testabile.

### 5.4 Verifica audit log

```bash
# Controllare gli eventi registrati nel database audit
docker compose exec audit psql -U audituser -d auditdb \
  -c "SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT 5;"
# Output atteso: righe con timestamp, endpoint /search, params, client_ip

# Controllare il file append-only
docker compose exec audit-log cat /audit-data/audit.log
# Output atteso: una riga JSON per ogni ricerca effettuata
```

### 5.5 Test di robustezza audit (evento non perso)

```bash
# 1. Fermare il consumer
docker compose stop audit-log
# Output atteso: Container audit-log stopped

# 2. Eseguire alcune ricerche (dal browser o con curl)
curl "http://localhost:3000/search?nome=chiara"
# Output atteso: risposta normale — UX non degradata

# 3. Verificare che gli eventi siano in coda su Redis
docker compose exec cache redis-cli llen audit_queue
# Output atteso: numero > 0 (eventi in attesa)

# 4. Riavviare il consumer
docker compose start audit-log

# 5. Attendere qualche secondo, poi verificare che la coda sia vuota
docker compose exec cache redis-cli llen audit_queue
# Output atteso: 0 (tutti gli eventi consumati)

# 6. Verificare che gli eventi siano nel database
docker compose exec audit psql -U audituser -d auditdb \
  -c "SELECT count(*) FROM audit_log;"
# Output atteso: numero incrementato rispetto a prima
```

### 5.6 Verifica isolamento di rete

```bash
# Il container db non deve essere raggiungibile dal frontend
docker compose exec frontend ping db
# Output atteso: ping: db: Name or address not found
# (db è solo sulla rete private, frontend solo sulla public)
```
Oppure, verificando passo-passo:
```bash
# Entra nel container frontend
docker compose exec frontend sh

# Una volta dentro, prova a raggiungere db
wget -q --timeout=3 db && echo "raggiungibile" || echo "non raggiungibile"

# Oppure installa ping al volo (solo per il test, non persiste)
apk add --no-cache iputils
ping -c 3 db
# Output atteso: ping: db: Name or address not found

# Prova anche con api (deve funzionare — stessa rete public)
ping -c 3 api
# Output atteso: risposta normale

# Esci
exit
```

---

## 6. Struttura del repository

```
.
├── docker-compose.yml
├── README.md
├── frontend/
│   └── index.html
├── api/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── main.py
├── audit-log/
│   ├── Dockerfile
│   └── consumer.py
└── db/
    ├── init.sql
    └── famiglie.csv
```
