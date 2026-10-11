ARG DUCKDB_VERSION=1.5.6
FROM duckdb/duckdb:${DUCKDB_VERSION} AS duckdb

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=duckdb /duckdb /usr/local/bin/duckdb
ENTRYPOINT ["duckdb"]
