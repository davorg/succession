# GitHub Copilot Instructions for Succession

## Project Overview

This is the codebase for [lineofsuccession.co.uk](https://lineofsuccession.co.uk/), a web application that displays the line of succession to the UK crown at various dates throughout history.

## Technology Stack

- **Language**: Perl 5
- **Web Framework**: Dancer2 (v0.204002+)
- **ORM**: DBIx::Class
- **Database**: SQLite (production uses MariaDB/MySQL)
- **Template Engine**: Template Toolkit
- **Object System**: Moose/Moo
- **Testing**: Test::More
- **CI/CD**: GitHub Actions
- **Containerization**: Docker

## Project Structure

```
succession/
├── .github/           # GitHub Actions workflows and configuration
├── bin/              # Utility scripts for data management and deployment
├── data/             # Database dumps and data files
├── Succession/       # Main Dancer2 application
│   ├── lib/         # Application modules
│   │   └── Succession/
│   │       ├── Schema/         # DBIx::Class schema (ORM)
│   │       │   ├── Result/     # Database table classes
│   │       │   └── ResultSet/  # Custom query methods
│   │       ├── App.pm          # Core application logic
│   │       ├── Model.pm        # Data model layer
│   │       └── Request.pm      # Request handling
│   ├── t/           # Test files
│   ├── views/       # Template Toolkit templates
│   └── public/      # Static assets (CSS, JS, images)
├── cpanfile         # Perl dependencies
└── Dockerfile       # Container configuration
```

## Key Components

### Database Schema

The application uses several main tables:
- `person` - Individuals in the succession line
- `title` - Titles held by people
- `sovereign` - Monarchs throughout history
- `position` - Current position in line of succession
- `exclusion` - People excluded from succession
- `change` and `change_date` - Historical changes to succession
- `succession_period` - Time periods with different succession rules

### Important Modules

- **Succession::App** - Main application class with business logic
- **Succession::Model** - Data access layer with caching (CHI)
- **Succession::Schema** - DBIx::Class schema base
- **Succession::Request** - Custom request object

### Utility Scripts (bin/)

Key scripts for data management:
- `add_person` - Add new person to database
- `add_child` - Add child relationship
- `get_change_dates` / `get_changes` - Calculate succession changes
- `get_positions` - Update current positions
- `dump_db` - Export database to SQL dump
- `load_db` - Load database from dump
- `db` - Direct database queries

## Development Workflow

### Setting Up Development Environment

1. Install Perl dependencies: `cpanm --installdeps .`
2. Set environment variables for database connection:
   - `SUCC_DB_USER`, `SUCC_DB_HOST`, `SUCC_DB_NAME`, `SUCC_DB_PASS`, `SUCC_DB_PORT`
3. Load test database: `bin/load_db`
4. Run tests: `prove -ISuccession/lib -v Succession/t`

### Testing

- Test files are in `Succession/t/`
- Run tests with: `prove -ISuccession/lib -v Succession/t`
- CI uses GitHub Actions with coverage reporting to Coveralls
- Tests require a database connection

### Database Changes

After making any data changes:
1. Run relevant update scripts (e.g., `bin/get_change_dates`, `bin/get_positions`)
2. Run `bin/dump_db` to export the database
3. Use `git diff` to verify only expected changes occurred

### Common Maintenance Tasks

See `UPDATES.md` for detailed procedures:

**New birth:**
- Add person to `person` table
- Add initial title to `title` table
- Run `bin/get_change_dates YYYY-MM-DD`
- Run `bin/get_changes YYYY-MM-DD`
- Run `bin/get_positions`

**Death:**
- Update death date in `person` table
- Run change date scripts
- If monarch: add new monarch to `sovereign` table with image

### Deployment

- Docker-based deployment
- Build container: `bin/build_container`
- Deploy: `bin/deploy_container`
- Service management: `bin/succession_service`

## Code Style and Conventions

- Use `strict` and `warnings` pragmas
- Modern Perl features via `use feature 'say'`, `use experimental 'signatures'`
- Object-oriented code uses Moose/Moo
- Database queries through DBIx::Class ORM
- Routes defined in `Succession/lib/Succession.pm`
- Templates use Template Toolkit syntax

## Important Notes

- The application caches data extensively (CHI with FastMmap or Memcached)
- Database is usually SQLite for development, MariaDB/MySQL in production
- Person data linked to Wikidata (QID identifiers)
- Historical data requires careful handling - changes affect succession calculations
- Always verify data changes don't corrupt historical succession records

## External Resources

- Live site: https://lineofsuccession.co.uk/
- Wikidata integration for biographical data
- Uses Genealogy::Relationship for relationship calculations

## CI/CD

GitHub Actions workflow (`.github/workflows/perltest.yml`):
- Runs on push/PR to master branch
- Sets up MariaDB service
- Installs dependencies via cpanm
- Runs test suite with coverage
- Reports coverage to Coveralls

## Environment Variables

- `SUCC_DB_USER` - Database username
- `SUCC_DB_HOST` - Database host
- `SUCC_DB_NAME` - Database name
- `SUCC_DB_PASS` - Database password
- `SUCC_DB_PORT` - Database port
- `PERL5LIB` - Should include `Succession/lib`
