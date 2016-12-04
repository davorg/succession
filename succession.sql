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
