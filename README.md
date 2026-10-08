[Download Page](https://data-explorer.oecd.org/vis?pg=0&bp=true&tm=%22%28TIVA%29%202025%20edition%22&snb=5&df[ds]=dsDisseminateFinalDMZ&df[id]=DSD_TIVA_FDVA%40DF_FDVA&df[ag]=OECD.STI.PIE&df[vs]=1.1&dq=.._T.W._T..A&pd=2015,&to[TIME_PERIOD]=false)

[FDVA_2019-2022.zip](https://webfs-sti.oecd.org/files/STI-PIE/TIVA/2025/FDVA/FDVA_2019-2022.zip)

Copy e.g. `FDVA_2022.csv` to `./data`.


Start duckdb shell:
```bash
docker compose run --rm duckdb duckdb tiva.duckdb
```

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

Or:
```sql
CREATE OR REPLACE TABLE tiva AS
FROM read_csv('/data/FDVA_2022.csv');
```


