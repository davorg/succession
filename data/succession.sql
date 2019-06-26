drop table if exists person;

create table person (
  id integer primary key auto_increment,
  name varchar(100) not null,
  born date not null,
  died date,
  parent integer null,
  family_order integer,
  sex enum('m', 'f') not null default 'm',
  wikipedia text,
  slug varchar(100) not null,
  foreign key (parent) references person(id)
);

create index person_parent on person (parent);

drop table if exists sovereign;

create table sovereign (
  id integer primary key auto_increment,
  start date not null,
  end date,
  person_id integer not null,
  foreign key (person_id) references person(id)
);

create index sovereign_start on sovereign (start);
create index sovereign_end   on sovereign (end);

drop table if exists title;

create table title (
  id integer primary key auto_increment,
  title varchar(255),
  start date,
  end date,
  person_id integer not null,
  is_default smallint not null default 0,
  foreign key (person_id) references person(id)
);

create index title_start      on title (start);
create index title_end        on title (end);
create index title_is_default on title (is_default);
create index title_person_id  on title (person_id);

drop table if exists exclusion;

create table exclusion (
  id integer primary key auto_increment,
  start date,
  end date,
  person_id integer not null,
  reason enum('i', 'c', 'mc') not null,
  foreign key (person_id) references person(id)
);

create index exclusion_start     on exclusion (start);
create index exclusion_end       on exclusion (end);
create index exclusion_person_id on exclusion (person_id);

drop table if exists change_date;

create table change_date (
  id integer primary key  auto_increment,
  change_date date,
  succession varchar(255)
);

create index change_date_change_date on change_date (change_date);

