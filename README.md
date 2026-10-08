# TIVA over SPARQL (Ontop)

Serve OECD **TIVA** (Trade in Value Added) annual statistics as a virtual Linked Data graph and query them with **SPARQL**.

The data is never transformed into RDF. Instead, [Ontop](https://ontop-vkg.org/) (an ontology-based data access engine) maps a relational table in **DuckDB** to an **SDMX / QB** data cube on the fly, so every SPARQL query is rewritten into SQL against the database.

## How it fits together

```
FDVA_2022.csv  ──►  DuckDB  (./run/tiva.duckdb, table `tiva`)
                         │
                         │  read-only JDBC
                         ▼
                      Ontop  ──R2RML (QB/SDMX)──►  virtual RDF graph
                         │
                         └──►  SPARQL  http://localhost:8080
```

## Open TODOS

* Vocabulary still uses example namespace. Needs consolidation.
* Tiva Areas are NOT countries; therefore a mapping tiva-area -> country iso3 code is needed - e.g. via overlapsWith.

## Requirements

- Docker + Docker Compose

## 1. Download the data

Grab the OECD TIVA *Final Demand Value Added by Activity* (FDVA) CSV and drop it into `./data/`:

- [Data Explorer – TIVA 2025 edition](https://data-explorer.oecd.org/vis?pg=0&bp=true&tm=%22%28TIVA%29%202025%20edition%22&snb=5&df[ds]=dsDisseminateFinalDMZ&df[id]=DSD_TIVA_FDVA%40DF_FDVA&df[ag]=OECD.STI.PIE&df[vs]=1.1&dq=.._T.W._T..A&pd=2015,&to[TIME_PERIOD]=false)
- [FDVA 2019–2022 (zip)](https://webfs-sti.oecd.org/files/STI-PIE/TIVA/2025/FDVA/FDVA_2019-2022.zip)

For example, copy `FDVA_2022.csv` to `./data`.

## 2. Load it into DuckDB

Start a DuckDB shell:

```bash
docker compose run --rm duckdb duckdb tiva.duckdb
```

Inside the shell, load the CSV into the `tiva` table:

```sql
CREATE TABLE tiva (
    DATAFLOW VARCHAR,
    MEASURE VARCHAR,
    TIME_PERIOD INTEGER,
    VALUE_ADDED_SOURCE_AREA VARCHAR,
    VALUE_ADDED_SOURCE_ACTIVITY VARCHAR,
    FINAL_DEMAND_AREA VARCHAR,
    FINAL_DEMAND_ACTIVITY VARCHAR,
    OBS_VALUE DOUBLE,
    UNIT_MEASURE VARCHAR,
    UNIT_MULT INTEGER,
    FREQ VARCHAR
);

COPY tiva FROM '/data/FDVA_2022.csv' (HEADER TRUE);
```

Or, let DuckDB infer the schema:

```sql
CREATE OR REPLACE TABLE tiva AS
FROM read_csv('/data/FDVA_2022.csv');
```

The database is written to `./run/tiva.duckdb`.

## 3. Start the endpoint

```bash
docker compose up -d ontop
```

Ontop loads the R2RML mapping (`ontop/tiva.r2rml.ttl`), opens a read-only JDBC connection to DuckDB (`ontop/tiva.properties`), and serves SPARQL on port `8080` at `http://localhost:8080`.

## 4. Query it

```bash
curl -s 'http://localhost:8080' \
     --data-urlencode 'query=PREFIX qb: <http://purl.org/linked-data/cube#>
                        SELECT (COUNT(*) AS ?n) WHERE { ?o a qb:Observation }' \
     -H 'Accept: application/json'
```

Each data row is exposed as a `qb:Observation`. Filter on any of the dimensions below to pull real values, e.g. match on `ex:indicator`, `sdmx-dimension:refPeriod`, `ex:valueAddedSourceArea`, … and read the value from `sdmx-measure:obsValue`.

## Modeled dimensions

| Dimension / attribute | Predicate | CSV column |
| --- | --- | --- |
| indicator | `ex:indicator` | `MEASURE` |
| reference period | `sdmx-dimension:refPeriod` | `TIME_PERIOD` |
| frequency | `sdmx-dimension:freq` | `FREQ` |
| source area | `ex:valueAddedSourceArea` | `VALUE_ADDED_SOURCE_AREA` |
| source activity | `ex:valueAddedSourceActivity` | `VALUE_ADDED_SOURCE_ACTIVITY` |
| demand area | `ex:finalDemandArea` | `FINAL_DEMAND_AREA` |
| demand activity | `ex:finalDemandActivity` | `FINAL_DEMAND_ACTIVITY` |
| value (measure) | `sdmx-measure:obsValue` | `OBS_VALUE` |
| unit | `sdmx-attribute:unitMeasure` | `UNIT_MEASURE` |
| multiplier | `sdmx-attribute:unitMult` | `UNIT_MULT` |

Code lists (area, activity, indicator, frequency, unit, multiplier) are generated as `skos:ConceptScheme`s from the distinct column values, and the cube is described as a `qb:DataStructureDefinition`.

## Files

| File | Role |
| --- | --- |
| `docker-compose.yaml` | `duckdb` + `ontop` services |
| `ontop/tiva.r2rml.ttl` | R2RML mapping: `tiva` → QB/SDMX cube |
| `ontop/tiva.properties` | JDBC URL/driver, read-only flag, query logging |

## Notes

- Only rows with a non-null `OBS_VALUE` are exposed as observations.
- `ONTOP_LOG_LEVEL: debug` (already set in `docker-compose.yaml`) logs the original SPARQL and the generated SQL — handy for debugging.
