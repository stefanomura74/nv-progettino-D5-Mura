import redis
import psycopg2
import json
import os
import time
from datetime import datetime, timezone

REDIS_HOST = os.getenv("AUDIT_REDIS_HOST", "cache")
DB_HOST = os.getenv("AUDIT_HOST")
DB_USER = os.getenv("AUDIT_USER")
DB_PASS = os.getenv("AUDIT_PASS")
DB_NAME = os.getenv("AUDIT_NAME")
LOG_FILE = "/audit-data/audit.log"

def get_db():
    return psycopg2.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        dbname=DB_NAME
    )

def init_db():
    retries = 10
    while retries > 0:
        try:
            conn = get_db()
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS audit_log (
                    id SERIAL PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL,
                    endpoint VARCHAR(255),
                    params JSONB,
                    client_ip VARCHAR(50)
                )
            """)
            conn.commit()
            cur.close()
            conn.close()
            print("[AUDIT] Database pronto")
            return
        except Exception as e:
            print(f"[AUDIT] DB non pronto, riprovo... ({e})")
            retries -= 1
            time.sleep(3)
    raise Exception("[AUDIT] Database non raggiungibile")

def write_to_db(event):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        """INSERT INTO audit_log (timestamp, endpoint, params, client_ip)
           VALUES (%s, %s, %s, %s)""",
        (
            event["timestamp"],
            event["endpoint"],
            json.dumps(event["params"]),
            event["client_ip"]
        )
    )
    conn.commit()
    cur.close()
    conn.close()

def write_to_file(event):
    with open(LOG_FILE, "a") as f:
        f.write(json.dumps(event) + "\n")

def main():
    init_db()
    r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
    print("[AUDIT] Consumer avviato, in ascolto su audit_queue...")

    while True:
        try:
            # BLPOP blocca fino a quando arriva un evento (timeout 5s)
            result = r.blpop("audit_queue", timeout=5)
            if result is None:
                continue

            _, raw = result
            event = json.loads(raw)

            write_to_db(event)
            write_to_file(event)
            print(f"[AUDIT] Evento registrato: {event}")

        except Exception as e:
            print(f"[AUDIT] Errore: {e}")
            time.sleep(2)

if __name__ == "__main__":
    main()