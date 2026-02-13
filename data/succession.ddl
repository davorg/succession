CREATE TABLE sqlite_stat1(tbl,idx,stat);
CREATE TABLE IF NOT EXISTS "change" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "person_id" integer NOT NULL,
  "change_date_id" integer NOT NULL,
  "description" text,
  FOREIGN KEY ("change_date_id") REFERENCES "change_date"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY ("person_id") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE TABLE IF NOT EXISTS "change_date" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "change_date" date,
  "succession" varchar(255)
);
CREATE TABLE IF NOT EXISTS "exclusion" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "start" date,
  "end" date,
  "person_id" integer NOT NULL,
  "reason" enum,
  FOREIGN KEY ("person_id") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE TABLE IF NOT EXISTS "person" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "born" date NOT NULL,
  "died" date,
  "parent" integer,
  "family_order" integer,
  "sex" enum NOT NULL DEFAULT 'm',
  "wikipedia" text,
  "slug" varchar(100),
  "wikidata_qid" varchar(32), last_audited_datetime datetime null,
  FOREIGN KEY ("parent") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE TABLE IF NOT EXISTS "position" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "person_id" integer NOT NULL,
  "position" integer NOT NULL,
  "start" date,
  "end" date,
  FOREIGN KEY ("person_id") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE TABLE IF NOT EXISTS "sovereign" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "start" date NOT NULL,
  "end" date,
  "person_id" integer NOT NULL,
  "image" char(40),
  "image_attr" varchar(1000),
  FOREIGN KEY ("person_id") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE TABLE IF NOT EXISTS "title" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "title" varchar(255),
  "start" date,
  "end" date,
  "person_id" integer NOT NULL,
  "is_default" smallint NOT NULL DEFAULT 0,
  FOREIGN KEY ("person_id") REFERENCES "person"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX "change_idx_change_date_id" ON "change" ("change_date_id");
CREATE INDEX "change_idx_person_id" ON "change" ("person_id");
CREATE INDEX "exclusion_idx_person_id" ON "exclusion" ("person_id");
CREATE INDEX "person_idx_parent" ON "person" ("parent");
CREATE UNIQUE INDEX "uq_person_qid" ON "person" ("wikidata_qid");
CREATE INDEX "position_idx_person_id" ON "position" ("person_id");
CREATE INDEX "sovereign_idx_person_id" ON "sovereign" ("person_id");
CREATE INDEX "title_idx_person_id" ON "title" ("person_id");
CREATE TABLE succession_period (
  id        INTEGER PRIMARY KEY,
  from_date DATE NOT NULL,
  to_date   DATE   -- NULL = "still in force"
, person_id       INTEGER REFERENCES person(id), change_position INTEGER, change_type     TEXT);
CREATE TABLE succession_entry (
  period_id INTEGER NOT NULL REFERENCES succession_period(id),
  rank      INTEGER NOT NULL,    -- 1 = first in line, etc.
  person_id INTEGER NOT NULL REFERENCES person(id),
  PRIMARY KEY (period_id, rank)
);
CREATE INDEX idx_succ_entry_person
  ON succession_entry(person_id);
CREATE INDEX idx_succ_period_range
  ON succession_period(from_date, to_date);
