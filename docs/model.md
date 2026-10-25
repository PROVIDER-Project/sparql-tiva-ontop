# OECD TiVA FDVA 2022 (2025 edition): model and country links

Command examples run from the repository root.

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

### Area memberships

The original `database/load.sql` also loads `database/tiva-area-mapping.csv` into
`tiva_area_membership`, keyed by `(AREA_CODE, MEMBER_CODE)`. The Maven generator bind mounts the CSV at `/opt/ontop/input/tiva-area-mapping.csv`.
Its metadata file records the source and extraction rules: the OECD TiVA 2023
Indicators Guide, Tables A.1 and A.2, printed pages 43 and 44. These are 2023
memberships using current codes, not verified 2025 membership definitions.
The missing 2025 economy additions particularly affect Africa, Other regions,
Non-OECD and residual coverage. The old-2021 code-alias CSV is not loaded.

The loader resolves nested memberships to economy leaves in `tiva_area_country`,
keyed by `(AREA_CODE, COUNTRY_CODE)`. R2RML exposes these pairs using
`ex:hasCountry`, with shared country IRIs `https://example.org/country/{ISO3}`.
It emits no labels, types or descriptive triples for country resources; a
separate authoritative dataset supplies those descriptions. A single-column
country-code index supports reverse lookups. For example:

```sparql
PREFIX ex: <https://example.org/tiva/vocab/>
SELECT ?area WHERE {
  ?area ex:hasCountry <https://example.org/country/CAN> .
}
```

The result includes Canada's own `.../tiva/area/CAN` resource and groups such as
NAFTA, OECD, APEC and G20. Country-level areas have identity links. Nested
G20/EU27_2020 membership is flattened and deduplicated, so France's multiple
paths create only one G20 country link. Mapping endpoints are included in the
area code list even when absent from a fact subset.

The 2023 group definitions remain unchanged. AGO, COD, STP and ARE are recognized
as separately represented 2025 economy codes for identity links only; they do
not silently update the older group definitions. WXD is residual and has no
country link. Domestic (`D`) needs observation context. World (`W`) has no
explicit country enumeration in this CSV, so it also produces no fixed links.
Consequently these links are not a complete area-to-country map for the 2025
edition, and they do not allocate aggregate values to countries.

CSV or SQL changes require a new database artifact and endpoint image.
Regenerate with Maven, choose a new immutable database version, then rebuild
the endpoint. The build completion marker does not track changes automatically. A missing CSV,
duplicate pair or invalid populated membership fails the transactional rebuild.


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
