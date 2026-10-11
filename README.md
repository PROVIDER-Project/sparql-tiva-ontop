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

## Mapping design goals and constraints

This design keeps RDF virtual while making broad triple queries streamable and
selective subject/object lookups indexable. Preserve these choices when changing
the mapping:

- **Avoid unnecessary `DISTINCT` under strict semantics.** RDF triples must be
  unique even without SPARQL `DISTINCT`. `tiva-lenses.json` declares the
  observation composite and local-name keys; `tiva-constraints.lst` exposes
  relational keys. `load.sql` deduplicates small code lists once, with one
  mapping each for combined source/demand areas and activities. Keep these keys
  truthful and retain `ontop.cardinalityMode=STRICT`.
- **Keep the IRI prefix visible and the lookup key indexable.** Ontop inverts a
  slash-separated template with several placeholders into predicates on its
  individual fields. A composite/expression index does not provide DuckDB's
  single-column ART lookup scan. Instead, `load.sql` stores one reversible,
  hyphen-separated `OBSERVATION_LOCAL_NAME`, and `tiva.r2rml.ttl` uses
  `.../observation/{OBSERVATION_LOCAL_NAME}`. Ontop retains the constant prefix
  and rewrites a fixed subject to one indexed equality. Escape component `~`,
  `-`, and `/` as documented below: a slash inside one placeholder would be
  R2RML-escaped, and unescaped component hyphens could cause key collisions.
  Avoid replacing this with an opaque full-IRI column or SQL prefix
  concatenation; the latter remained a concatenation filter in Ontop 5.5 tests.
- **Index the values actually compared by generated SQL.** Stored `YEAR`,
  `UNIT_MULT_CODE`, and `OBS_VALUE_LEXICAL` avoid query-time casts on object
  lookups. Build the single-column indexes after ingestion and run `ANALYZE`.
  Code-list primary keys already create indexes.

For future changes, inspect Ontop's reformulated SQL: the broad triple query
should avoid unnecessary `DISTINCT`, and selective lookups should compare a
stored column directly to a constant. Check DuckDB's plan for index use and
verify RDF terms and numeric filters/aggregates. Ontop 5.5/DuckDB 1.5.6 fixture
checks passed these targets; full-dataset memory and latency remain unmeasured.
Common objects and unbound triple enumeration may still require scans. See the
query-planning section below for identifier changes, rebuild steps, and tools.

## Open TODOS

* Vocabulary still uses example namespace. Needs consolidation.
* Tiva Areas are NOT countries; therefore a mapping tiva-area -> country iso3 code is needed - e.g. via overlapsWith.

## Requirements

- Docker + Docker Compose (v2, for `depends_on` with `condition`)

The first start downloads the dataset (~421MB, zstd-compressed) into `./data/`, pulls the published `aksw/duckdb-shell:1.5.6` image, and prepares the database in `./run/`. Derived columns and indexes increase its size, so allow space for the indexed database as well as the source file.

## Start the endpoint

```bash
docker compose up -d
```

This runs three services in order:

1. `fetch` downloads the OECD TIVA *Final Demand Value Added by Activity* (FDVA) zstd-compressed CSV into `./data/FDVA.csv.zst`, and the DuckDB JDBC driver into `./jdbc/` (used by `ontop`). Each download is skipped if a nonempty completed file already exists. New downloads are written to `.part` files and renamed only after curl succeeds; a failed download stops `fetch` and prevents `load` from starting. A later attempt overwrites the partial file.
2. `load` checks `./run/tiva.duckdb.complete` and a nonempty `./run/tiva.duckdb`. If both exist, it exits successfully without opening DuckDB. Otherwise it executes `ontop/load.sql`, reads the source file straight into DuckDB (zstd is decompressed on the fly), and rebuilds `tiva` plus seven small dataset/code-list tables in one transaction in `./run/tiva.duckdb`. The code-list tables have primary keys; area and activity codes combine source and demand values once during loading. The loader also derives the observation local name and lexical columns, builds lookup indexes after ingestion, and runs `ANALYZE`. It creates the completion marker only after DuckDB successfully commits and exits.
3. `ontop` loads the R2RML mapping (`ontop/tiva.r2rml.ttl`), observation lens (`ontop/tiva-lenses.json`), and constraints, opens a read-only JDBC connection to DuckDB (`ontop/tiva.properties`), and serves SPARQL on port `8080` at `http://localhost:8080/sparql`.

Both the database and its completion marker live in the bind-mounted `./run/`
directory and survive `docker compose down` / `up`. Subsequent starts skip loading
and let Ontop serve the prepared database read-only. A failed load leaves no
marker and fails the `load` service, so Ontop does not start. A marker with a
missing or empty database triggers loading again.

The generic `aksw/duckdb-shell:1.5.6` image is built from
`docker/duckdb-shell/Dockerfile`: the pinned official DuckDB binary is copied
into Debian with `/bin/sh`, its C++ runtime, and CA certificates. Its default
entrypoint is `duckdb`; override it with `--entrypoint /bin/sh` for shell scripts.
The image contains no TIVA data or loading logic. Compose mounts
`loader/load-duckdb.sh` and overrides the entrypoint to run it. Compose uses the
published image directly, with no local build. For image development, the build context is only `./docker/duckdb-shell`, excluding data
and database directories.
`loader/load-duckdb.sh` implements the marker lifecycle. The marker is a manual
completion flag: source, SQL, and mapping changes do not automatically invalidate
it. Delete it explicitly when a rebuild is needed.

## Publishing the generic image

The GitHub Actions workflow `.github/workflows/duckdb-shell.yml` builds and
smoke-tests the image on pull requests. On `main` pushes affecting the image or
workflow, and manual runs from `main`, it publishes Linux amd64 and arm64 images
as `aksw/duckdb-shell:1.5.6`, `:latest`, and `:sha-<full commit>`.
Set the repository Actions variable `DOCKERHUB_USERNAME` to a Docker Hub account
with push access to `aksw/duckdb-shell`, and the Actions secret `DOCKERHUB_TOKEN`
to that account's access token. No credentials belong in this repository.
Publication requires committing and pushing the workflow and configuring those
credentials. Keep the Dockerfile version, workflow tags, Compose image, and JDBC
version aligned when upgrading. Version tags are updated on publication; use a
commit tag or image digest when deployment must be immutable.

For a manual publication after `docker login`:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t aksw/duckdb-shell:1.5.6 -t aksw/duckdb-shell:latest \
  --push ./docker/duckdb-shell
```

Compose uses the prebuilt image by default. To explicitly refresh the local image:

```bash
docker compose pull load
docker compose up -d
```

For Flux/Kubernetes, use `image: aksw/duckdb-shell:1.5.6` (preferably pinned by
digest) in an init container or load Job. Mount the loading script and SQL through
a ConfigMap, source data and database through volumes, and set
`command: ["/bin/sh", "/opt/loader/load-duckdb.sh"]` with the database and SQL
paths as `args`. Ontop must start after loading finishes and mount the same
persistent database read-only. Kubernetes pulls the published image; it does
not build the Dockerfile. The completion marker must live beside the database
on its persistent volume so pod recreation skips completed loading.

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

To force a rebuild, stop Ontop, delete only the completion marker, and run the
loader. The existing database need not be deleted; the SQL rebuild is
transactional. Start Ontop again only if loading succeeds:

```bash
docker compose stop ontop
rm -f ./run/tiva.duckdb.complete
docker compose run --rm load && docker compose up -d --no-deps ontop
```

Running `docker compose run --rm load` with the marker present intentionally
skips loading. Marker deletion also schedules a rebuild on the next ordinary
`docker compose up`. If an already prepared database has no marker when adopting
this change, the loader rebuilds it once.

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

Code lists (area, activity, indicator, frequency, unit, multiplier) are generated as `skos:ConceptScheme`s from the small unique tables built during loading, and the cube is described as a `qb:DataStructureDefinition`. Source and demand areas share one area mapping; source and demand activities share one activity mapping.

## Files

| File | Role |
| --- | --- |
| `docker-compose.yaml` | `fetch` + `load` + `ontop` services |
| `ontop/tiva.r2rml.ttl` | R2RML mapping: `tiva` → QB/SDMX cube |
| `ontop/tiva.properties` | JDBC URL/driver, read-only flag, query logging |
| `ontop/tiva-constraints.lst` | unique columns for `tiva` and the dataset/code-list tables |
| `ontop/tiva-lenses.json` | observation filter and explicit composite/local-name keys |
| `ontop/load.sql` | transactional rebuild of facts, derived lookup columns, code lists, and indexes |
| `docker/duckdb-shell/Dockerfile` | generic DuckDB CLI with a shell and runtime |
| `.github/workflows/duckdb-shell.yml` | test and publish `aksw/duckdb-shell` to Docker Hub |
| `tests/test_duckdb_shell.sh` | real image and loader smoke test |
| `loader/load-duckdb.sh` | skip completed databases and mark successful loads |
| `tests/test_loader.py` | marker lifecycle tests without Docker or the dataset |

## Notes

- Only rows with a non-null `OBS_VALUE` are exposed as observations.
- `ONTOP_LOG_LEVEL: debug` (already set in `docker-compose.yaml`) logs the original SPARQL and the generated SQL — handy for debugging.

## Query planning and duplicate elimination

The default is `ontop.cardinalityMode=STRICT`. An RDF graph contains each triple
once, so Ontop may introduce SQL duplicate elimination even when the SPARQL
query has no `DISTINCT`.

The observation mapping uses the `tiva_observations` BasicLens. The loader stores
`YEAR` as a string and constructs an `OBSERVATION_LOCAL_NAME` from the eight key
fields in this order: DATAFLOW, MEASURE, FREQ, YEAR, VALUE_ADDED_SOURCE_AREA,
VALUE_ADDED_SOURCE_ACTIVITY, FINAL_DEMAND_AREA, FINAL_DEMAND_ACTIVITY. The lens
explicitly declares both the composite key and the local-name key. These retain
the data-uniqueness assumption already present in the original `tiva` constraint;
the lens declares keys to Ontop rather than enforcing them in DuckDB. Any change
of source data must preserve that key. Rows missing an observation IRI component
are filtered out, as R2RML would not generate their subject; `OBS_VALUE` must
also be non-null.

**Observation identifiers have changed** from slash-separated key components to
a single hyphen-separated local name. For example:

```text
Before: https://example.org/tiva/observation/FDVA/M/A/2019/A/X/B/Y
After:  https://example.org/tiva/observation/FDVA-M-A-2019-A-X-B-Y
```

Inside a component, `~`, `-`, and `/` become `~7E`, `~2D`, and `~2F` respectively,
with `~` escaped first. This makes the encoding reversible and keeps separator
hyphens unambiguous. The R2RML template applies normal escaping to the complete
local name. The constant observation prefix remains in the subject template,
so Ontop can distinguish it from the dataset and code-list prefixes. Dataset,
code-list and metadata IRIs, and observation literal datatypes, are unchanged.

Code-list deduplication happens once during loading. Each small table has an
enforced primary key, and the external constraint file also exposes that key to
Ontop. These lists include codes from all source rows, including rows with null
observation values, as the original mappings did.

### Subject and object lookup indexes

DuckDB's ART index scans support single-column equality and `IN` filters;
composite and expression indexes do not currently provide these lookup scans.
The loader therefore stores derived values in ordinary columns and creates
12 single-column ART indexes on `tiva`:

- `OBSERVATION_LOCAL_NAME` for observation subjects;
- `DATAFLOW`, `MEASURE`, `YEAR`, `FREQ`, `VALUE_ADDED_SOURCE_AREA`,
  `VALUE_ADDED_SOURCE_ACTIVITY`, `FINAL_DEMAND_AREA`, `FINAL_DEMAND_ACTIVITY`,
  `UNIT_MEASURE`, and `UNIT_MULT_CODE` for the mapped IRI/year objects;
- `OBS_VALUE_LEXICAL` for exact RDF observation-value objects.

`YEAR`, `UNIT_MULT_CODE`, and `OBS_VALUE_LEXICAL` are stored string conversions of
TIME_PERIOD, UNIT_MULT, and OBS_VALUE. Mapping these directly avoids query-time
casts that prevent index use. The numeric CSV columns remain available for SQL
analysis. The code-list/dataset tables already have ART indexes through their
primary keys, so no duplicate indexes are created on them.

A fixed subject such as the new example above translates to an equality on
`OBSERVATION_LOCAL_NAME`, rather than eight separate component predicates.
Selective mapped object lookups can similarly use their stored column indexes.
Unbound `?s ?p ?o` queries are scans; indexes do not make enumeration cheap.
Objects matching a large fraction of the facts may also use scans: DuckDB
selects the plan by estimated cardinality. Indexes and stored columns increase
load time, disk space, and runtime memory; measure these costs on the full
source dataset before changing index-scan thresholds.

See [DuckDB indexing](https://duckdb.org/docs/guides/performance/indexing) and
[CREATE INDEX](https://duckdb.org/docs/current/sql/statements/create_index).

### Applying this change to an existing database

The new mapping needs the derived columns, indexes, and code-list tables. Stop the endpoint before
rebuilding the database, then recreate it with the updated configuration:

```bash
docker compose stop ontop
rm -f ./run/tiva.duckdb.complete
docker compose run --rm load && docker compose up -d --no-deps --force-recreate ontop
```

### Inspecting the SQL without executing the large query

For a temporary development endpoint, run the Ontop CLI with `--dev` and pass
both the constraint and lens files:

```bash
ontop endpoint --dev \
  -m ontop/tiva.r2rml.ttl \
  -p ontop/tiva.properties \
  -c ontop/tiva-constraints.lst \
  --lenses ontop/tiva-lenses.json
```

The CLI example assumes a JDBC URL pointing to your local database and the
DuckDB JDBC jar in the CLI's `jdbc/` directory. The committed properties use
`/data/tiva.duckdb`, the path inside the Docker service.

```bash
curl -fsS 'http://localhost:8080/ontop/reformulate' \
  --data-urlencode 'query=SELECT * WHERE { ?s ?p ?o } LIMIT 1000' \
  > /tmp/tiva-query.sql
```

Compare the SQL for `LIMIT 10` and `LIMIT 1000`, and use DuckDB `EXPLAIN`
(without `ANALYZE`) to inspect the plan without executing the query. Check for
duplicate elimination on the observation branches or above the whole union.
The additional keys and disjoint mappings improve the available uniqueness
information; they do not guarantee that every Ontop plan will omit `DISTINCT`.

For a diagnostic comparison, temporarily change the properties setting to
`ontop.cardinalityMode=LOOSE` and restart the endpoint. This relaxes preservation
of result multiplicities: duplicate triples can affect counts, sums, and limit
results. Restore `STRICT` for normal use. `LOOSE` does not remove explicit
`DISTINCT` inside source SQL. Keep `ontop.disableLimitOptimization` at its default
`false`.

References: [Ontop lenses](https://ontop-vkg.org/guide/advanced/lenses),
[Ontop 5.5.0 configuration keys](https://raw.githubusercontent.com/ontop/ontop/ontop-5.5.0/core/model/src/main/resources/property_description.json),
[Ontop CLI](https://ontop-vkg.org/guide/cli.html).

## Loader lifecycle tests

Run from the repository with Python 3:

```bash
python3 -m unittest discover -s tests -v
```

These tests check successful completion and skipping, explicit reload after
marker deletion, retry after a failed load, stale markers, and failure to create
a nonempty database. They use a fake DuckDB executable and do not load the dataset.
