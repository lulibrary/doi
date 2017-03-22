Mint
==
About
-
Mint is a Rails app for minting Digital Object Identifiers (DOIs).

How does it work?
-
The only input required by the user is a Pure Id. Using this, Mint retrieves
metadata from Pure Web Services and performs a cross-walk to the metadata schema
for the target DOI Registration Agent. DOIs and URLs (to which the DOIs resolve)
are generated automatically for Pure portal and together with the metadata, are
used to mint a DOI with the target DOI Registration Agent. DOI minting
transactions are stored in a local database. DOIs can be reserved for deferred
minting.

Supported DOI registration agents
-
![DataCite logo](/app/assets/images/datacite-logo.png)

Mint currently works with DataCite which provides DOIs for dataset publications.
DataCite's metadata schema version 4.0 is supported.


Ruby version
-
2.1


Database creation
-
Hosted databases such as Postgres will need to be created, together with a
database user.

Database initialization
-
Create the database tables:
```
$ rake db:migrate ($ rake db:migrate RAILS_ENV="production", for production)
```
Populate lookup tables:
```
$ rake db:seed ($ rake db:seed RAILS_ENV="production", for production)
```

Configuration
-
#### Environment
An environment configuration file is required in the root directory by the gem
dotenv. For a  Rails development environment name the file
```env.development```. For  a production environment name the file
```env.production```. An example file is provided in the root
```env.environment.example``` which is the development version with the
credentials removed.

#### Certificate
The environment file references a PEM file which is used for SSL connections
with DOI Registration Agents and Pure Web Services.

Create the self-signed certificate:
```
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout doi.key -out doi.crt
```
Create the PEM:
```
$ cat doi.crt doi.key > doi.pem
```

#### Rails secret
Randomised string used by Rails to verify the integrity of signed cookies.
Generate a new one:
```
$ rake secret
```

Batch update
-
Use the Rails console to update all the current metadata records. Output is
saved to the environment log.
```
load './scripts/batch_metadata.rb'
```
Use the Rails console to update all the URLS for the DOIs. Output is
saved to the environment log.
```
load './scripts/batch_url.rb'
```

Troubleshooting
-
Mint generates DOIs with an integer as the last part which is formed by
incrementing a counter stored in a local database for that resource type.
>In the unlikely event that the local database should go out of sync (e.g.
caused by local database failure), a remote DOI
would already exist which would prevent the new one being minted with that DOI
string. If this is the case, the ```count``` column in the table
```resource_types``` should be adjusted to be the actual number of
dois minted for that resource type. When a new DOI is minted it will then increment
this number. The alternative to this would be to do a request to count the
number of DOIs returned before minting, but this has not been implemented.