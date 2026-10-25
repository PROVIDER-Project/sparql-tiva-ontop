# OECD TiVA FDVA 2022 (2025 edition): preloaded DuckDB

Maven builds and publishes `org.aksw.data.tiva:tiva-fdva-2022-duckdb:duckdb.zst:0.0.1`. The source is pinned to
`org.aksw.data.thirdparty.org.oecd.tiva:FDVA_2019-2022:1`. The generated output is
`target/tiva.duckdb.zst`; software, mappings and image versions are independent.

## Build, install and deploy

Requires Maven, JDK 17+, Docker and enough memory/disk for the facts, derived
columns, indexes and compression. DuckDB CLI 1.5.6 and endpoint JDBC 1.5.6.0
remain aligned with the previous setup. Run from this folder:

```sh
mvn package
mvn install
mvn deploy -DaltDeploymentRepository=aksw-data-releases::https://maven.inf-ai.duckdns.org/releases
```

Set a new POM version before publishing each immutable release; configure
credentials using the matching Maven server ID. No artifact has been deployed
by this migration. To reuse an already generated archive, use
`mvn -DskipGenerateData=true install` or `deploy`; do not combine that with `clean`.

To install into the endpoint's default project-local cache, from the repo root:

```sh
mvn -f database/pom.xml -Dmaven.repo.local="$PWD/endpoint/.cache/maven/repository" install
make -C endpoint build
```

The build lifecycle follows FAOSTAT:

1. `generate-resources`: Dependency Plugin resolves the pinned input artifacts
   through Maven, respecting repositories, mirrors and credentials.
2. `process-resources`: Docker Maven Plugin builds/runs a dedicated DuckDB
   generator with explicit inputs, SQL and auxiliary policy data. It waits for
   successful commit and process exit before proceeding.
3. `prepare-package`: a separate zstd compressor container reads the completed
   database volume, checks the archive, copies only the compressed result to the
   host and removes the build containers/anonymous volume.
4. `package`: Build Helper attaches the archive with type `duckdb.zst`.

The load guard skips only a nonempty database with a successful completion marker.
A fresh Maven generation uses a fresh volume. Failure leaves no success marker;
compression uses a partial file and preserves any previous complete output.
Build failures may leave Docker containers for diagnosis; inspect/remove the
specific failed build containers and their volumes before retrying.

The plugin versions match the checked FAOSTAT setup: Docker Maven 0.49.0,
Dependency 3.11.0, Build Helper 3.6.2, Clean 3.5.0, Install/Deploy 3.2.0.
Properties include `duckdb.image`, `data.repository.url`, `generator.timeout`
(milliseconds; default 7200000), `compressor.timeout` (1800000), `zstd.level` (6)
and `zstd.threads` (2). Source coordinates and source version are pinned in the POM.

## Scope and provenance

The source coordinate names a 2019–2022 bundle, but the selected classifier
`FDVA_2022` contains **2022 only**, from the 2025 TiVA edition. This migration does
not silently broaden the input selection or adopt the old runtime database.

The local `tiva-area-mapping.csv` extraction remains based on the **2023** guide;
its memberships are not verified against the 2025 edition. Added 2025 economy
identity links do not update aggregate memberships. Preserve the distinctions
between economies, residuals, aggregates, World and contextual Domestic.
See [membership provenance](tiva-area-mapping.csv.meta.md).

Attribution: OECD (2025), Trade in Value Added (TiVA), Final Demand Value Added
by Activity, 2022; source https://webfs-sti.oecd.org/files/STI-PIE/TIVA/2025/FDVA/FDVA_2019-2022.zip
(accessed 11 October 2026). Membership extraction: OECD (2023), Guide to OECD TiVA
Indicators, Tables A.1/A.2 (extracted 13 October 2026).

The artifact retains [OECD data terms](https://www.oecd.org/en/about/terms-conditions.html)
and the guide's applicable terms; it does not assert a blanket CC BY licence.
Retain the OECD acknowledgment and require downstream recipients to retain it.
This is an adaptation of an original work by the OECD. The opinions expressed
and arguments employed in this adaptation should not be reported as representing
the official views of the OECD or of its Member countries.

The former runtime database is about 13 GB; a rebuild also needs temporary/index
space, a compressed output and Docker storage. Do not budget only the archive's
size. Full-data generation must be scheduled on a machine with sufficient space.

## Tests

Fixture checks use real DuckDB through JDBC, without the full source dataset.
From the repository root, resolve the test driver and run:

```sh
mvn org.apache.maven.plugins:maven-dependency-plugin:3.11.0:copy \
  -Dartifact=org.duckdb:duckdb_jdbc:1.5.6.0:jar \
  -DoutputDirectory="$PWD/database/target/test-dependencies"
python3 -m unittest discover -s database/tests -v
```

`DUCKDB_JDBC_JAR=/absolute/path/duckdb_jdbc-1.5.6.0.jar` overrides the driver path.
Loader and compression tests also cover skipping, failures and archive replacement.
To exercise the real Maven/Docker lifecycle with small, clearly named outputs:

```sh
python3 database/tests/create_fixture.py /tmp/provider-fixture-inputs
mvn -f database/pom.xml -P'!resolve-inputs' \
  -Dinput.directory=/tmp/provider-fixture-inputs \
  -Ddatabase.filename=tiva-fixture.duckdb package
```

This deactivates source resolution only for that explicit fixture run. Never
install/deploy a fixture under production release coordinates. Fixture archives
have a different filename; the ordinary production attachment cannot silently
reuse them. Normal builds leave `resolve-inputs` enabled.

## Future option: ORAS publishing

As documented in the FAOSTAT sibling, an optional `publish-oci` profile could
publish the same archive/version as a plain-file OCI artifact. One candidate is
[`com.tosan.plugin:oras-maven-plugin`](https://github.com/Tosan/oras-maven-plugin),
whose `push` goal invokes an installed ORAS CLI and can use Maven settings for
registry credentials. That profile is not implemented. Maven remains the default
for local installs, remote publication, mirrors and endpoint resolution.
