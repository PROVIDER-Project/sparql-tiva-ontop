#!/bin/sh
set -eu
sh /opt/build/resolve-artifact.sh org.aksw.data.tiva tiva-fdva-2022-duckdb \
    "$TIVA_VERSION" duckdb.zst tiva.duckdb.zst
sh /opt/build/resolve-artifact.sh org.duckdb duckdb_jdbc \
    "$DUCKDB_JDBC_VERSION" jar duckdb_jdbc.jar
