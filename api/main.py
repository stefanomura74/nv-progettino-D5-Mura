from flask import Flask, request, jsonify
from flasgger import Swagger
import psycopg2
import psycopg2.extras
import redis
import json
import os
import threading
from datetime import datetime, timezone

app = Flask(__name__)
Swagger(app)

def get_db():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASS"),
        dbname=os.getenv("DB_NAME")
    )

def get_redis():
    return redis.Redis(
        host=os.getenv("AUDIT_REDIS_HOST", "cache"),
        port=6379,
        decode_responses=True
    )

def audit_event(endpoint, params, client_ip):
    def _push():
        try:
            event = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "endpoint": endpoint,
                "params": params,
                # hashing parameters for privacy before sending to Redis
                #"params": {k: (hash(v) if isinstance(v, str) else v) for k, v in params.items()},
                "client_ip": client_ip
            }
            r = get_redis()
            r.rpush("audit_queue", json.dumps(event))
        except Exception as e:
            print(f"[AUDIT] Errore push Redis: {e}")
    
    t = threading.Thread(target=_push, daemon=True)
    t.start()

@app.route('/search', methods=['GET'])
def search_persone():
    """
    Cerca persone per nome
    ---
    parameters:
      - name: nome
        in: query
        type: string
        required: true
        description: Nome da cercare
    responses:
      200:
        description: Lista di persone trovate
      404:
        description: Nessun risultato trovato
      400:
        description: Parametro nome mancante
    """
    nome = request.args.get('nome', '').strip()
    client_ip = request.headers.get('X-Forwarded-For', request.remote_addr)

    audit_event(
        endpoint='/search',
        params={'nome': nome},
        client_ip=client_ip
    )

    if not nome:
        return jsonify({'error': 'Parametro nome obbligatorio'}), 400

    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        "SELECT nome, anno_nascita, cittadinanza, sesso FROM famiglie WHERE nome ILIKE %s",
        ('%' + nome + '%',)
    )
    risultati = cur.fetchall()
    cur.close()
    conn.close()

    if not risultati:
        return jsonify({'error': 'Nessun risultato trovato'}), 404

    return jsonify([dict(r) for r in risultati])

@app.after_request
def add_cors(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    return response

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)