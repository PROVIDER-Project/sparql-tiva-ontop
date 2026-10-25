# tiva-area-mapping.csv

## Source

- Publisher: OECD, Directorate for Science, Technology and Innovation.
- Document: Guide to OECD Trade in Value Added (TiVA) Indicators, 2023 edition, November 2023.
- [Official PDF](https://www.oecd.org/content/dam/oecd/en/topics/policy-sub-issues/trade-in-value-added/tiva-indicators-guide-2023.pdf).
- [Table A.2: Regions and country groups, page 44](https://www.oecd.org/content/dam/oecd/en/topics/policy-sub-issues/trade-in-value-added/tiva-indicators-guide-2023.pdf#page=44). Printed page 44 is also PDF page 44 (zero-based page index 43).
- [Table A.1: Country coverage, page 43](https://www.oecd.org/content/dam/oecd/en/topics/policy-sub-issues/trade-in-value-added/tiva-indicators-guide-2023.pdf#page=43), used to expand the numbered country ranges for OECD and WXOECD.
- Extraction date: 2026-10-13.
- This CSV is a locally prepared extraction, not a CSV published by OECD. No standalone official mapping CSV was found during this search; this does not establish that none exists.

## Code convention and edition

The area_code column uses Table A.2’s current Code column, introduced in 2023. These names are also present in the local 2025 FDVA dataset. Memberships here remain those of the accessible 2023 edition, not verified 2025 memberships.

Both files use the same 2023 membership definitions. Only the aggregate area_code aliases differ. Member economy codes come from Table A.1 and are retained as published, including WXD. The old-code file therefore does not silently replace WXD with a historical ROW alias not specified in these source tables.

## CSV schema

UTF-8, comma-separated, LF line endings, one header row. 313 data rows covering all 19 entries of Table A.2.

| Column | Meaning |
| --- | --- |
| area_code | Aggregate or contextual area identifier in the selected code convention. |
| member_code | One explicitly listed constituent economy or aggregate. Empty when the table supplies no fixed member list. |
| member_kind | economy, residual, aggregate, world, or contextual. |

The key is (area_code, member_code). Repeated area_code values express one-to-many membership. Source order is retained. This is direct membership, not a sovereign-country overlap mapping. Individual economy identity rows (such as DEU → DEU) are not added because Table A.2 describes groups; direct economy codes can be handled as identities separately.

## Extraction rules and special cases

- OECD: expand Countries 1 to 38 using Table A.1.
- WXOECD: expand Countries 39 to 77 using Table A.1, including WXD.
- G20: the source lists EU27 as a nested constituent. Normalize that shorthand to EU27_2020, the defined group code. Preserve the nested constituent rather than invent a direct country list. Footnote 4 says France, Germany and Italy are excluded from this EU constituent because they are separately listed. When deriving a set of touched economies, union the explicit countries and EU27_2020 and deduplicate. Never sum observations from this mapping as if these entries were disjoint.
- WXD: residual Rest of the World, not an ISO country code. It occurs as a member of WXOECD and W_O. No underlying ISO-country enumeration is supplied on these pages, so none is invented.
- W / WLD: Table A.2 leaves its member list empty. Retain one row with an empty member_code and member_kind=world. A complete world expansion would need separate derivation and residual handling.
- D / DXD: contextual Domestic dummy partner. Retain one row with an empty member_code and member_kind=contextual. It cannot be assigned a fixed country list independently of the observation.
- APEC: the source explicitly excludes Papua New Guinea because it is outside the 2023 TiVA coverage.
- EU28 and EU15 retain the United Kingdom as specified by the source, rather than using present-day institutional membership.
- Economy distinctions are preserved, including CHN, HKG and TWN. No mapping to sovereign states is inferred.

## Compatibility with the local 2025 dataset

The local tiva_area table contains AGO, COD, STP and ARE in addition to the economy codes in Table A.1 of this 2023 PDF. Do not use these files as a complete verified 2025 mapping. In particular, F, W_O and WXOECD require checking against 2025 coverage, and residual coverage may change. No 2025 changes have been mixed into this extraction.

## Validation

Checked table membership counts (OECD 38, WXOECD 39, APEC 20, ASEAN 10, EU27_2020 27, EU28 28, EU15 15, EA19 19), 77 unique Table A.1 economy/residual codes, all 19 Table A.2 entries, valid member references and uniqueness of each area/member pair. Both code conventions have identical memberships.
