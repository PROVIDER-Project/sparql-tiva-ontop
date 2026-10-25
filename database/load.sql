-- Rebuild the facts and their small code lists together. No RDF is materialized.
BEGIN TRANSACTION;

-- A reversible component encoding keeps '-' exclusive to key separators and
-- keeps '/' out of the single-segment local name. Escape '~' before using it.
-- Remaining characters receive normal R2RML escaping in the subject template.
CREATE OR REPLACE TEMP MACRO tiva_local_component(component) AS
    REPLACE(REPLACE(REPLACE(CAST(component AS VARCHAR), '~', '~7E'),
                    '-', '~2D'), '/', '~2F');

CREATE OR REPLACE TABLE tiva (
    DATAFLOW VARCHAR, MEASURE VARCHAR, TIME_PERIOD INTEGER,
    VALUE_ADDED_SOURCE_AREA VARCHAR, VALUE_ADDED_SOURCE_ACTIVITY VARCHAR,
    FINAL_DEMAND_AREA VARCHAR, FINAL_DEMAND_ACTIVITY VARCHAR,
    OBS_VALUE DOUBLE, UNIT_MEASURE VARCHAR, UNIT_MULT INTEGER, FREQ VARCHAR, YEAR VARCHAR,
    OBSERVATION_LOCAL_NAME VARCHAR,
    OBS_VALUE_LEXICAL VARCHAR, UNIT_MULT_CODE VARCHAR
);
-- Normalize values to the table types before constructing the local name.
INSERT INTO tiva
WITH typed AS (
    SELECT
        CAST(DATAFLOW AS VARCHAR) AS DATAFLOW,
        CAST(MEASURE AS VARCHAR) AS MEASURE,
        CAST(TIME_PERIOD AS INTEGER) AS TIME_PERIOD,
        CAST(VALUE_ADDED_SOURCE_AREA AS VARCHAR) AS VALUE_ADDED_SOURCE_AREA,
        CAST(VALUE_ADDED_SOURCE_ACTIVITY AS VARCHAR) AS VALUE_ADDED_SOURCE_ACTIVITY,
        CAST(FINAL_DEMAND_AREA AS VARCHAR) AS FINAL_DEMAND_AREA,
        CAST(FINAL_DEMAND_ACTIVITY AS VARCHAR) AS FINAL_DEMAND_ACTIVITY,
        CAST(OBS_VALUE AS DOUBLE) AS OBS_VALUE,
        CAST(UNIT_MEASURE AS VARCHAR) AS UNIT_MEASURE,
        CAST(UNIT_MULT AS INTEGER) AS UNIT_MULT,
        CAST(FREQ AS VARCHAR) AS FREQ
    FROM read_csv('/data/FDVA.csv.zst', header=true)
), with_year AS (
    SELECT *, CAST(TIME_PERIOD AS VARCHAR) AS YEAR FROM typed
)
SELECT *,
    CASE WHEN OBS_VALUE IS NOT NULL AND DATAFLOW IS NOT NULL AND MEASURE IS NOT NULL AND FREQ IS NOT NULL AND YEAR IS NOT NULL AND VALUE_ADDED_SOURCE_AREA IS NOT NULL AND VALUE_ADDED_SOURCE_ACTIVITY IS NOT NULL AND FINAL_DEMAND_AREA IS NOT NULL AND FINAL_DEMAND_ACTIVITY IS NOT NULL
    THEN tiva_local_component(DATAFLOW) || '-' || tiva_local_component(MEASURE) || '-' || tiva_local_component(FREQ) || '-' || tiva_local_component(YEAR) || '-' || tiva_local_component(VALUE_ADDED_SOURCE_AREA) || '-' || tiva_local_component(VALUE_ADDED_SOURCE_ACTIVITY) || '-' || tiva_local_component(FINAL_DEMAND_AREA) || '-' || tiva_local_component(FINAL_DEMAND_ACTIVITY)
    END AS OBSERVATION_LOCAL_NAME,
    CAST(OBS_VALUE AS VARCHAR) AS OBS_VALUE_LEXICAL,
    CAST(UNIT_MULT AS VARCHAR) AS UNIT_MULT_CODE
FROM with_year;

CREATE OR REPLACE TABLE tiva_dataset (DATAFLOW VARCHAR PRIMARY KEY);
INSERT INTO tiva_dataset
SELECT DISTINCT DATAFLOW FROM tiva WHERE DATAFLOW IS NOT NULL;

-- The CSV uses current area codes and the documented 2023 memberships.
-- World and Domestic have no fixed member list and therefore no edges.
-- Keep residual and nested aggregate members as areas, not country identities.
CREATE OR REPLACE TABLE tiva_area_membership (
    AREA_CODE VARCHAR,
    MEMBER_CODE VARCHAR,
    MEMBER_KIND VARCHAR NOT NULL CHECK (MEMBER_KIND IN ('economy', 'residual', 'aggregate')),
    PRIMARY KEY (AREA_CODE, MEMBER_CODE)
);
INSERT INTO tiva_area_membership
SELECT area_code, member_code, member_kind
FROM read_csv('/opt/ontop/input/tiva-area-mapping.csv', header=true,
              columns={'area_code': 'VARCHAR', 'member_code': 'VARCHAR', 'member_kind': 'VARCHAR'})
WHERE member_code IS NOT NULL;

CREATE OR REPLACE TABLE tiva_area (CODE VARCHAR PRIMARY KEY);
INSERT INTO tiva_area
SELECT VALUE_ADDED_SOURCE_AREA FROM tiva WHERE VALUE_ADDED_SOURCE_AREA IS NOT NULL
UNION
SELECT FINAL_DEMAND_AREA FROM tiva WHERE FINAL_DEMAND_AREA IS NOT NULL
UNION
SELECT AREA_CODE FROM tiva_area_membership
UNION
SELECT MEMBER_CODE FROM tiva_area_membership;

-- Resolve nested memberships to ISO3-coded economy leaves. No ISO3 codes
-- are invented for the residual WXD, World or contextual Domestic entries.
CREATE OR REPLACE TABLE tiva_area_country (
    AREA_CODE VARCHAR,
    COUNTRY_CODE VARCHAR,
    PRIMARY KEY (AREA_CODE, COUNTRY_CODE)
);
INSERT INTO tiva_area_country
WITH RECURSIVE
country_codes(CODE) AS (
    SELECT MEMBER_CODE FROM tiva_area_membership WHERE MEMBER_KIND = 'economy'
    UNION
    -- These separately represented economies were added in the 2025 edition.
    -- This supplements country-area identity links only, not 2023 group lists.
    SELECT CODE FROM (VALUES ('AGO'), ('COD'), ('STP'), ('ARE')) AS added(CODE)
),
reach(AREA_CODE, MEMBER_CODE) AS (
    SELECT AREA_CODE, MEMBER_CODE FROM tiva_area_membership
    UNION
    SELECT r.AREA_CODE, m.MEMBER_CODE
    FROM reach r JOIN tiva_area_membership m ON r.MEMBER_CODE = m.AREA_CODE
)
SELECT r.AREA_CODE, r.MEMBER_CODE
FROM reach r JOIN country_codes c ON r.MEMBER_CODE = c.CODE
UNION
SELECT a.CODE, a.CODE
FROM tiva_area a JOIN country_codes c ON a.CODE = c.CODE;
CREATE INDEX tiva_area_country_country_code_idx ON tiva_area_country (COUNTRY_CODE);

CREATE OR REPLACE TABLE tiva_activity (CODE VARCHAR PRIMARY KEY);
INSERT INTO tiva_activity
SELECT VALUE_ADDED_SOURCE_ACTIVITY FROM tiva WHERE VALUE_ADDED_SOURCE_ACTIVITY IS NOT NULL
UNION
SELECT FINAL_DEMAND_ACTIVITY FROM tiva WHERE FINAL_DEMAND_ACTIVITY IS NOT NULL;

CREATE OR REPLACE TABLE tiva_indicator (CODE VARCHAR PRIMARY KEY);
INSERT INTO tiva_indicator
SELECT DISTINCT MEASURE FROM tiva WHERE MEASURE IS NOT NULL;

CREATE OR REPLACE TABLE tiva_frequency (CODE VARCHAR PRIMARY KEY);
INSERT INTO tiva_frequency
SELECT DISTINCT FREQ FROM tiva WHERE FREQ IS NOT NULL;

CREATE OR REPLACE TABLE tiva_unit (CODE VARCHAR PRIMARY KEY);
INSERT INTO tiva_unit
SELECT DISTINCT UNIT_MEASURE FROM tiva WHERE UNIT_MEASURE IS NOT NULL;

CREATE OR REPLACE TABLE tiva_unit_multiplier (UNIT_MULT INTEGER PRIMARY KEY);
INSERT INTO tiva_unit_multiplier
SELECT DISTINCT UNIT_MULT FROM tiva WHERE UNIT_MULT IS NOT NULL;

-- Single-column ART indexes for object equality/IN filters. Primary keys
-- already index the small dataset/code-list tables. Build after bulk loading.
CREATE INDEX tiva_observation_local_name_idx ON tiva (OBSERVATION_LOCAL_NAME);
CREATE INDEX tiva_dataflow_idx ON tiva (DATAFLOW);
CREATE INDEX tiva_measure_idx ON tiva (MEASURE);
CREATE INDEX tiva_year_idx ON tiva (YEAR);
CREATE INDEX tiva_freq_idx ON tiva (FREQ);
CREATE INDEX tiva_value_added_source_area_idx ON tiva (VALUE_ADDED_SOURCE_AREA);
CREATE INDEX tiva_value_added_source_activity_idx ON tiva (VALUE_ADDED_SOURCE_ACTIVITY);
CREATE INDEX tiva_final_demand_area_idx ON tiva (FINAL_DEMAND_AREA);
CREATE INDEX tiva_final_demand_activity_idx ON tiva (FINAL_DEMAND_ACTIVITY);
CREATE INDEX tiva_obs_value_lexical_idx ON tiva (OBS_VALUE_LEXICAL);
CREATE INDEX tiva_unit_measure_idx ON tiva (UNIT_MEASURE);
CREATE INDEX tiva_unit_mult_code_idx ON tiva (UNIT_MULT_CODE);

ANALYZE;

COMMIT;
