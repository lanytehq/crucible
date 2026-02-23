# lanyte-crucible (Seed)

This seed represents the intended structure for the **public** `lanytehq/lanyte-crucible` repo.

Goals:

- Contract-first: specs + schemas land before implementations.
- Kitfly renders `docs/` (like Hugo/Docusaurus); machine artifacts live in `schemas/` and `config/`.

## Local Preview

```bash
kitfly dev . --port 4012
```

## Structure

- `docs/` rendered documentation (specs, policies, ADRs)
- `schemas/` machine-consumable JSON Schemas (SSOT)
- `config/` machine-consumable catalogs/taxonomies (SSOT)

## Licensing And Marks

Copy the standard Crucible pattern:

- CC0 for docs/data/schemas
- MIT OR Apache-2.0 for code/scripts
- Trademark notice reserving `Lanyte`/`LanyteHQ`
