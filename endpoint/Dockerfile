# Artifacts are resolved by `make resolve` before Docker packaging.
ARG ENDPOINT_VERSION=0.0.1
ARG TIVA_VERSION=0.0.1
ARG DUCKDB_JDBC_VERSION=1.5.6.0

FROM debian:bookworm-slim AS extraction-tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends zstd \
    && rm -rf /var/lib/apt/lists/*
FROM extraction-tools AS database
COPY target/artifacts/tiva.duckdb.zst target/artifacts/tiva.duckdb.zst.sha1 /artifacts/
RUN zstd --decompress /artifacts/tiva.duckdb.zst -o /artifacts/tiva.duckdb \
    && test -s /artifacts/tiva.duckdb \
    && rm /artifacts/tiva.duckdb.zst \
    && chmod 0444 /artifacts/tiva.duckdb \
    && touch -d @0 /artifacts/tiva.duckdb

# Stable data layer first, before driver or endpoint-specific configuration.
# This target can also be built/tagged for downstream FROM-based customization.
FROM ghcr.io/provider-project/provider-ontop:5.5.0-1 AS data-base
COPY --from=database --chown=ontop:ontop /artifacts/tiva.duckdb /data/tiva.duckdb
COPY --from=database --chown=ontop:ontop /artifacts/tiva.duckdb.zst.sha1 /opt/ontop/input/

FROM data-base AS endpoint-base
COPY --chown=ontop:ontop target/artifacts/duckdb_jdbc.jar /opt/ontop/jdbc/duckdb_jdbc.jar
COPY --chown=ontop:ontop target/artifacts/duckdb_jdbc.jar.sha1 /opt/ontop/input/

# Small endpoint-specific layers follow all shared data/runtime layers.
FROM endpoint-base AS endpoint
ARG ENDPOINT_VERSION

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*
USER ontop

COPY --chown=ontop:ontop LICENSE LICENSING.md /opt/ontop/licenses/
COPY --chown=ontop:ontop third-party/ /opt/ontop/licenses/third-party/

COPY --chown=ontop:ontop ontop/tiva.r2rml.ttl.in ontop/namespaces.sh ontop/expand.sh ontop/start.sh ontop/tiva.properties ontop/tiva-constraints.lst ontop/tiva-lenses.json /opt/ontop/input/
COPY --chown=ontop:ontop README.md ontop/tiva-area-mapping.csv.meta.md /opt/ontop/input/

ENV ONTOP_MAPPING_FILE=/tmp/provider-tiva.r2rml.ttl \
    ONTOP_PROPERTIES_FILE=/opt/ontop/input/tiva.properties \
    ONTOP_CONSTRAINT_FILE=/opt/ontop/input/tiva-constraints.lst \
    ONTOP_LENSES_FILE=/opt/ontop/input/tiva-lenses.json \
    ONTOP_LOG_LEVEL=debug
# Expand namespace defaults/overrides, then delegate through provider-ontop's property configuration.
ENTRYPOINT ["/bin/sh", "/opt/ontop/input/start.sh"]

ARG TIVA_VERSION
ARG DUCKDB_JDBC_VERSION
LABEL org.opencontainers.image.title="PROVIDER TIVA SPARQL endpoint" \
      org.opencontainers.image.source="https://github.com/PROVIDER-Project/sparql-tiva-ontop" \
      org.opencontainers.image.description="Ontop endpoint with a preloaded OECD TiVA FDVA 2022 (2025 edition) database" \
      org.opencontainers.image.version="${ENDPOINT_VERSION}" \
      org.aksw.tiva.artifact.version="${TIVA_VERSION}" \
      org.aksw.tiva.artifact.checksum.algorithm="SHA-1" \
      org.aksw.tiva.data.license="https://www.oecd.org/en/about/terms-conditions.html" \
      org.aksw.tiva.data.terms="https://www.oecd.org/en/about/terms-conditions.html" \
      org.aksw.tiva.jdbc.version="${DUCKDB_JDBC_VERSION}"
