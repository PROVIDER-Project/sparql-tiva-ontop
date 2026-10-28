# OECD TiVA FDVA 2022 (2025 edition) over SPARQL

Serve OECD TiVA FDVA 2022 (2025 edition) as a virtual RDF data cube using Ontop and DuckDB.
The [database build](database/README.md) publishes a compressed Maven artifact;
the [endpoint build](endpoint/README.md) packages it with the mappings.

## Build and run

Requires Maven, a JDK, GNU Make and Docker with BuildKit/Compose.
From the repository root:

```sh
mvn -f database/pom.xml -P local deploy
make -C endpoint up
```

The `local` profile publishes the dataset to `database/target/m2` and skips
installation into your normal Maven repository. Without it, `mvn install` and
`mvn deploy` also put the dataset alongside your other Maven artifacts
(usually in `~/.m2/repository`). Source and plugin dependencies still use Maven's
configured cache in either case.

The endpoint uses `database/target/m2` by default when present, with its own
Maven cache and remote repositories available too. Override this folder with
`DATABASE_REPOSITORY`, or set it empty to disable it:

```sh
make -C endpoint build DATABASE_REPOSITORY=/path/to/m2
```

Settings can also go in `endpoint/.env`; see
[endpoint configuration](endpoint/README.md#configuration).
The service runs at [localhost:8080/sparql](http://localhost:8080/sparql).
Use `make -C endpoint down` to stop it and `make -C endpoint help` for all targets.

TiVA needs substantial memory and disk: the previous raw database was about
13 GB, before temporary files, indexes, compression and Docker storage.

## Publish

Database and endpoint versions are independent. Set a new POM version for each
immutable data release, then publish with Maven credentials from `settings.xml`:

```sh
mvn -f database/pom.xml deploy \
  -DaltDeploymentRepository=aksw-data-releases::https://maven.inf-ai.duckdns.org/releases
make -C endpoint login GHCR_USER=YOUR_GITHUB_USERNAME
make -C endpoint publish VERSION=0.0.2 DATABASE_VERSION=0.0.1
```

Current database coordinates:
`org.aksw.data.tiva:tiva-fdva-2022-duckdb:duckdb.zst:0.0.1`.
Building an endpoint locally does not publish it.

## Design and scope

The build follows [FAOSTAT](../sparql-faostat-ontop/README.md): source data and
scripts are bind mounted into the generation containers; completion markers
skip repeated loading and compression. The endpoint image contains an unpacked,
read-only database, with data layers before JDBC and configuration.

TiVA contains **FDVA 2022 only**, from the 2025 edition. Group memberships
come from the 2023 guide and are not verified against 2025 definitions.
Added economy identity links do not silently update those memberships.

After changing database inputs or loading settings, rebuild with
`mvn -f database/pom.xml -P local clean deploy`. This removes `target/m2` too.
Use new release versions for changed published data; Maven may reuse cached
releases. See [model and country-link details](docs/model.md).
The sibling [Helm chart](../helm-charts/charts/ontop/README.md) deploys the
selected endpoint image independently.

## Tests

See [database tests](database/README.md#tests) for fixtures and script checks.
`make -C endpoint check` verifies orchestration; `make -C endpoint test` also
builds and queries an isolated endpoint container.

## Sources and licence

Original project material is licensed under [Apache-2.0](LICENSE).
[Licensing notes](LICENSING.md) distinguish third-party/data terms and declare
that the information about those terms was derived with AI assistance.

OECD (2025), Trade in Value Added (TiVA), Final Demand Value Added by Activity,
2022 (accessed 11 October 2026). Membership extraction: OECD (2023), *Guide to
OECD TiVA Indicators*, Tables A.1/A.2 (extracted 13 October 2026).
[OECD terms](https://www.oecd.org/en/about/terms-conditions.html) and the guide's
applicable terms remain in force; no blanket CC BY licence is asserted.
Retain OECD acknowledgment and require downstream recipients to retain it.
This is an adaptation of an original work by the OECD. The opinions expressed
and arguments employed in this adaptation should not be reported as representing
the official views of the OECD or of its Member countries.
See the [membership provenance record](database/tiva-area-mapping.csv.meta.md).
