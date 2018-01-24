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

drop table if exists sovereign;

create table sovereign (
  id integer primary key auto_increment,
  start date not null,
  end date,
  person_id integer not null,
  foreign key (person_id) references person(id)
);

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

drop table if exists exclusion;

create table exclusion (
  id integer primary key auto_increment,
  start date,
  end date,
  person_id integer not null,
  reason enum('i', 'c', 'mc') not null,
  foreign key (person_id) references person(id)
);

drop table if exists change_date;

create table change_date (
  id integer primary key  auto_increment,
  change_date date
);
