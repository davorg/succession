drop table if exists person;

create table person (
  id integer primary key auto_increment,
  name varchar(50) not null,
  born date not null,
  died date,
  parent integer null,
  family_order integer,
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

dopr table if exists title;

create table title (
  id integer primary key auto_increment,
  title varchar(255),
  start date,
  end date,
  person_id integer not null,
  is_default smallint not null default 0,
  foreign key (person_id) references person(id)
);