# Licensing

## Project material

Copyright 2026 the contributors to this repository.

Original project code, scripts, mappings, configuration, tests and documentation
are licensed under the [Apache License, Version 2.0](LICENSE), except material
identified as third-party content or derived data below. Third-party notices
remain applicable to their respective material.

## Third-party licence information

The identification and interpretation of third-party licence information in
this repository and its artifact metadata were AI-assisted in an attempt to
be as accurate as possible. It may contain
errors and is not legal advice. Authoritative upstream licences, notices and
dataset-specific terms govern; this summary does not replace or amend them.

- [Ontop](https://github.com/ontop/ontop/blob/version5/LICENSE.txt): Apache-2.0.
- [DuckDB](https://github.com/duckdb/duckdb/blob/v1.5.6/LICENSE) and
  [DuckDB JDBC](https://github.com/duckdb/duckdb-java/blob/main/LICENSE): MIT.
  Their copyright and permission notice is included in
  [third-party/duckdb-LICENSE](third-party/duckdb-LICENSE).
- Container base images and their operating-system/runtime packages retain
  their own licences and notices. The project licence does not relicense them.

### OECD TiVA data and guide-derived memberships

FDVA 2022 data from the 2025 TiVA edition and the membership extraction from
the 2023 guide retain their applicable [OECD terms](https://www.oecd.org/en/about/terms-conditions.html).
No blanket CC BY or Apache-2.0 licence is asserted for these materials.
Retain OECD acknowledgment and carry that requirement forward to downstream
recipients, as required by the data terms. Dataset-specific third-party
restrictions remain applicable.

Attribution: OECD (2025), Trade in Value Added (TiVA), Final Demand Value Added
by Activity, 2022. Source:
https://webfs-sti.oecd.org/files/STI-PIE/TIVA/2025/FDVA/FDVA_2019-2022.zip
(accessed 11 October 2026). Membership extraction: OECD (2023), Guide to OECD
TiVA Indicators, Tables A.1/A.2 (extracted 13 October 2026).

This is an adaptation of an original work by the OECD. The opinions expressed
and arguments employed in this adaptation should not be reported as representing
the official views of the OECD or of its Member countries.

Transformations include typed values, lookup columns, indexes, deduplicated
code lists and country links. Memberships from the 2023 guide are not verified
against the 2025 edition; identity additions do not update group membership.
