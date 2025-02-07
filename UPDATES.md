# Updates

How to carry out some common (for some value of "common") updates.

## New birth

* Add the new person to the `person` table
* Add the new person's initial title to the `title` table
* Run `bin/get_change_dates YYYY-MM-DD` and `bin/get_changes YYYY-MM-DD`
* Run `bin/get_positions`

## Death

* Update the person table to add the date of death
* Run `bin/get_change_dates YYYY-MM-DD` and `bin/get_changes YYYY-MM-DD`
* Run `bin/get_positions`
* If it's the monarch who has died, then add the new monarch to the `sovereign` table (you'll need an image)

## After any data changes

* Run `bin/dump_db` to dump the database
* Run `git diff` to ensure the changes look sensible (only the database dump should have changed)
