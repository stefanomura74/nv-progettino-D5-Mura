CREATE TABLE famiglie (
    id INTEGER PRIMARY KEY,
    anno_nascita INTEGER,
    cittadinanza VARCHAR(50),
    nome VARCHAR(255),
    sesso CHAR(1),
    occorrenze INTEGER,
    cessato BOOLEAN,
    data_inizio_famiglia TIMESTAMP,
    data_fine_famiglia TIMESTAMP,
    convivenza BOOLEAN,
    aire BOOLEAN,
    maschi INTEGER,
    femmine INTEGER
);

COPY famiglie (id, anno_nascita, cittadinanza, nome, sesso, occorrenze, cessato, data_inizio_famiglia, data_fine_famiglia, convivenza, aire, maschi, femmine)
FROM '/data/famiglie.csv'
DELIMITER ','
CSV HEADER
NULL '';