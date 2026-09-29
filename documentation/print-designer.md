# Personalised print designer

`/print` is currently unlinked from the main navigation; a shop link is planned.
It provides a date selector, birth/succession ordering, example dates and
an initially blank preview. “Show me” fetches the watermarked PNG; loading,
validation and generation failures are displayed on the page. The initial
release is A3 only. It has no ordering, payment or interest-registration flow.

`/print.png?date=1962-09-07&order=succession` selects a root automatically.
The model starts with the monarch reigning on the date, then searches earlier
reigns in descending order. Still-living former monarchs are skipped. The first
family with at least 25 people wins; if none qualifies, the largest available
family is used (ties favour the later monarch).

The root, deceased contextual relatives and excluded people all count towards
the 30-person maximum. The selected display order is applied before taking the
first 30 rows. A depth-first prefix preserves each retained person's ancestors,
but can end partway through a branch. Birth and succession ordering can therefore
include different people near the cutoff. Rankings remain full succession
positions and can exceed 30.

Existing URLs with an explicit `sovereign_id` retain their full-tree behaviour,
including the existing oversized-layout rejection. `/print.svg` redirects to
the PNG endpoint. No public parameter disables the SPECIMEN watermark.

The renderer needs `rsvg-convert` and serif fonts, already included in the
Dockerfile and CI installation. The page uses the existing Bootstrap layout
and local `/js/print.js`. Unexpected server errors are logged but return a
generic message to visitors.

Relevant checks:

```
SUCC_DB_PATH="$PWD/data/los.sqlite" prove -ISuccession/lib Succession/t/022_succession_tree.t Succession/t/024_print_route.t Succession/t/025_print_designer.t
node --check Succession/public/js/print.js
```
