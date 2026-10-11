FROM duckdb/duckdb:1.5.6 AS duckdb

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=duckdb /duckdb /usr/local/bin/duckdb
COPY load-duckdb.sh /usr/local/bin/load-duckdb.sh
WORKDIR /workspace
ENTRYPOINT ["/bin/sh", "/usr/local/bin/load-duckdb.sh"]
