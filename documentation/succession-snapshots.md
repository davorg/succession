# Succession snapshots and exclusions

The home and date pages display thirty **eligible successors**, along with
excluded people encountered before the thirtieth successor. Display order and
succession rank are separate:

- `succession_entry` contains eligible people with contiguous ranks 1–30. Person
  histories and other ranked consumers retain this interface.
- `succession_display_entry` contains all displayed people in family order.
  `succession_rank` is null for exclusions; their reason comes from the dated
  exclusion record. Unborn and deceased people do not appear.
- `Model::succession_display_on_date` loads a snapshot, people, titles and
  exclusions in one query. `Model::succession_on_date` returns its eligible
  people. JSON-LD and MCP therefore continue to contain only eligible successors.
- Print ranks use the same generator with an unlimited prefix, so family prints
  can include successors beyond the thirtieth without changing their ranks.

`Succession::Snapshot` reads the genealogy into memory once. It follows the
sovereign's descendants, younger siblings and the younger branches of each
ancestor. The existing `family_order` determines sibling precedence; equal
values are resolved by birth date and then ID for reproducible output. An
excluded person's descendants are retained and checked against their own
exclusion records. Exclusions start inclusively and end exclusively; deaths
take effect on the death date, consistent with the application's end-of-day
dated views.

## Rebuilding after a data change

The generator considers births, deaths, reign boundaries and exclusion
boundaries, together with existing change dates. A new period starts when the
displayed prefix or an exclusion reason changes. Existing period IDs are kept
where their dates remain valid; redundant boundaries are removed. Change events
are regenerated from the source facts rather than the old truncated strings.

Preview the proposed changes without modifying the database:

```sh
bin/rebuild_succession --database data/los.sqlite --report /tmp/succession-plan.json
```

The report includes changed eligible lists, added and removed dates, and any
periods with fewer than thirty eligible people. To apply the plan:

```sh
bin/rebuild_succession --database data/los.sqlite --apply --report /tmp/succession-plan.json
SUCC_DB_PATH=data/los.sqlite bin/dump_db
```

For a reproducible historical audit, add `--through YYYY-MM-DD`. Rebuilding
through a date earlier than an existing period is rejected. `--limit` changes
the stored eligible cutoff; production uses the default of 30. `bin/mksucc`
is retained as an apply-mode wrapper around this generator, and the Wikidata
audit workflow rebuilds snapshots before dumping a changed database.

All replacement rows, periods and events are written in one transaction. An
invalid genealogy or failed insert leaves the existing snapshots intact.
Repeated rebuilds with the same source facts preserve IDs and produce the same
rows and events. The cache namespace includes the snapshot schema revision so
results from the earlier truncated lists are not reused.

## Initial repair of issues #177 and #178

The audit through 2026-10-12 rebuilt 283 periods, including 67 additional event
boundaries, and removed 57 redundant legacy boundaries. Ranked lists changed
at 144 retained dates. None of the rebuilt periods has fewer than thirty
eligible successors. The detailed before/after report is in
`documentation/succession-snapshot-audit.json`.

On 1990-01-01 the old snapshot had 27 successors because three exclusions were
removed from an already truncated list of 30. The corrected page has thirty
eligible successors and four exclusions (34 display rows): the fourth exclusion
is Lady Emily Shard, beyond the old cutoff. The additional eligible successors
are Alexander Lascelles, Edward Lascelles and James Lascelles.
