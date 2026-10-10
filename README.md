# TIVA over SPARQL (Ontop)

Serve OECD **TIVA** (Trade in Value Added) annual statistics as a virtual Linked Data graph and query them with **SPARQL**.

The data is never materialized as RDF. Instead, [Ontop](https://ontop-vkg.org/) (an ontology-based data access engine) maps a relational table in **DuckDB** to an **SDMX / QB** data cube on the fly, so every SPARQL query is rewritten into SQL against the database.

## How it fits together

```
FDVA.csv.zst  (downloaded by `fetch`)  ──►  DuckDB  (./run/tiva.duckdb, table `tiva`)
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

- Docker + Docker Compose (v2, for `depends_on` with `condition`)

The first start downloads the dataset (~421MB, zstd-compressed) into `./data/` and builds the database into `./run/` (about 400MB), so allow a few hundred MB of free space.

## Start the endpoint

```bash
docker compose up -d
```

This runs three services in order:

1. `fetch` downloads the OECD TIVA *Final Demand Value Added by Activity* (FDVA) zstd-compressed CSV into `./data/FDVA.csv.zst`, and the DuckDB JDBC driver into `./jdbc/` (used by `ontop`). Each download is skipped if a nonempty completed file already exists. New downloads are written to `.part` files and renamed only after curl succeeds; a failed download stops `fetch` and prevents `load` from starting. A later attempt overwrites the partial file.
2. `load` reads that file straight into DuckDB (zstd is decompressed on the fly) and (re)builds the `tiva` table in `./run/tiva.duckdb`.
3. `ontop` loads the R2RML mapping (`ontop/tiva.r2rml.ttl`), opens a read-only JDBC connection to DuckDB (`ontop/tiva.properties`), and serves SPARQL on port `8080` at `http://localhost:8080/sparql`.

On a later `docker compose up`, the downloads are skipped (the files are present) and the `tiva` table is rebuilt from the local file. The rebuild happens on every start because the `duckdb/duckdb` image ships no shell or other tooling to implement a "skip if already loaded" guard; reloading the ~64M-row file takes only a few seconds on a sufficiently modern machine.

## Query it

```bash
curl -s 'http://localhost:8080/sparql' \
     --data-urlencode 'query=PREFIX qb: <http://purl.org/linked-data/cube#>
                        SELECT (COUNT(*) AS ?n) WHERE { ?o a qb:Observation }' \
     -H 'Accept: application/json'
```

Each data row is exposed as a `qb:Observation`. Filter on any of the dimensions below to pull real values, e.g. match on `ex:indicator`, `sdmx-dimension:refPeriod`, `ex:valueAddedSourceArea`, … and read the value from `sdmx-measure:obsValue`.

## Manual / advanced

The `fetch` service downloads:

- FDVA dataset: https://maven.inf-ai.duckdns.org/releases/org/aksw/data/thirdparty/org/oecd/tiva/FDVA_2019-2022/1/FDVA_2019-2022-1-FDVA_2022.csv.zst
- DuckDB JDBC driver: https://repo.maven.apache.org/maven2/org/duckdb/duckdb_jdbc/1.5.6.0/duckdb_jdbc-1.5.6.0.jar

Other dataset sources, if you prefer:

- [Data Explorer – TIVA 2025 edition](https://data-explorer.oecd.org/vis?pg=0&bp=true&tm=%22%28TIVA%29%202025%20edition%22&snb=5&df[ds]=dsDisseminateFinalDMZ&df[id]=DSD_TIVA_FDVA%40DF_FDVA&df[ag]=OECD.STI.PIE&df[vs]=1.1&dq=.._T.W._T..A&pd=2015,&to[TIME_PERIOD]=false)
- [FDVA 2019–2022 (zip)](https://webfs-sti.oecd.org/files/STI-PIE/TIVA/2025/FDVA/FDVA_2019-2022.zip)

To rebuild the `tiva` table by hand:

```bash
docker compose run --rm load
```

or run DuckDB directly (zstd is decompressed on the fly; the table is created with explicit types and then populated):

```bash
docker run --rm \
  -v "$PWD/data:/data:ro" -v "$PWD/run:/workspace" \
  --entrypoint duckdb duckdb/duckdb:1.5.6 \
  tiva.duckdb \
  -c "CREATE OR REPLACE TABLE tiva (DATAFLOW VARCHAR, MEASURE VARCHAR, TIME_PERIOD INTEGER, VALUE_ADDED_SOURCE_AREA VARCHAR, VALUE_ADDED_SOURCE_ACTIVITY VARCHAR, FINAL_DEMAND_AREA VARCHAR, FINAL_DEMAND_ACTIVITY VARCHAR, OBS_VALUE DOUBLE, UNIT_MEASURE VARCHAR, UNIT_MULT INTEGER, FREQ VARCHAR);" \
  -c "INSERT INTO tiva SELECT * FROM read_csv('/data/FDVA.csv.zst', header=true);"
```

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
| `docker-compose.yaml` | `fetch` + `load` + `ontop` services |
| `ontop/tiva.r2rml.ttl` | R2RML mapping: `tiva` → QB/SDMX cube |
| `ontop/tiva.properties` | JDBC URL/driver, read-only flag, query logging |
| `ontop/tiva-constraints.lst` | primary key columns for the `tiva` table |

## Notes

- Only rows with a non-null `OBS_VALUE` are exposed as observations.
- `ONTOP_LOG_LEVEL: debug` (already set in `docker-compose.yaml`) logs the original SPARQL and the generated SQL — handy for debugging.
