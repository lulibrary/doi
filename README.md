Mint
==
About
-
Mint is a Rails app[^developer] for minting Digital Object Identifiers (DOIs).
 [^developer]: Adrian Albin-Clark, May 2015.

How does it work?
-
The only input required by the user is a Pure Id. Using this, Mint retrieves
metadata from Pure Web Services and performs a cross-walk to the metadata schema
for the target DOI Registration Agent. DOIs and URLs (to which the DOIs resolve)
are generated automatically, and together with the metadata, are used to mint a
DOI with the target DOI Registration Agent. DOI minting transactions are stored
in a local database.

Supported DOI registration agents
-
![](https://www.datacite.org/sites/all/themes/datacite/logo.png)
Mint currently works with DataCite which provides DOIs for dataset publications.
It could be extended to work with other agents although any variation in the
APIs would need to be taken into account.


Ruby version
-
ruby 2.1.2p95 (2014-05-08 revision 45877)

System dependencies
-
Rails 4.1.0

Database creation
-
Hosted databases such as Postgres will need to be created, together with a
database user.

Database initialization
-
Create the database tables:
```
$ rake db:migrate
```
Populate lookup tables:
```
$ rake db:seed
```


Deployment instructions
-
Change to the directory where this repository will be placed.

Clone the repository into that directory.
```
$ git clone https://aalbinclark@bitbucket.org/ditlul/doi.git
```

Configuration
-
#### Environment
An environment configuration file is required in the root directory by the gem
dotenv. For a  Rails development environment name the file
```env.development```. For  a production environment name the file
```env.production```. An example file is provided in the root
```env.environment.example``` which is the development version with the
credentials removed:
```
// DataCite API
DATACITE_ENDPOINT = https://test.datacite.org/mds
DATACITE_RESOURCE_DOI = /doi
DATACITE_RESOURCE_METADATA = /metadata
DATACITE_RESOURCE_MEDIA = /media
DATACITE_USERNAME = username
DATACITE_PASSWORD = password

// Datacite DOI for institution domains
DATACITE_DOI_IDENTIFIER = 10.4124

// Content in DataCite DOI after identifier
DATACITE_DOI_PREFIX = lancaster

// Content for URL before integer
DATACITE_URL_PREFIX = http://www.lancaster.ac.uk/library/rdm/data-catalogue

// Pure Web Services API
PURE_ENDPOINT = https://ciswebtest.lancaster.ac.uk/purewebservices/datasets/datasetid/
PURE_USERNAME = username
PURE_PASSWORD = password

// Local database
DB_ADAPTER = postgresql
DB_NAME = doi
DB_HOST = lib-dev.lancs.ac.uk
DB_USERNAME = username
DB_PASSWORD = password

// SSL
PEM = /home/albincla/ssl/doi.pem

// Rails secret
SECRET_KEY_BASE = 2bee8666341e6ecf0a50c1b3f5ddca427237dff2cc275c1de1891d2b434925cc39a272455c6ca82bd35f0db80a59f9060f6daad2241f1b72487ed7b347d2ce88
```
#### Certificate
The environment file references a PEM file which is used for SSL connections
with DOI Registration Agents and Pure Web Services.

Create the self-signed certificate:
```
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout doi.key -out
doi.crt
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

Troubleshooting
-
Mint generates DOIs with an integer as the last part which is formed by
incrementing a counter stored in a local database for that DOI
Registration Agent.
>In the unlikely event that the local database should go out of sync (e.g.
caused by local database failure) with a DOI Registration Agent, a remote DOI
would already exist which would prevent the new one being minted with that DOI
string. If this is the case, the ```count``` column in the table
```doi_registration_agent``` should be adjusted to be the actual number of
dois minted for that agent. When a new DOI is minted it will then increment
this number. The alternative to this would be to do a request to count the
number of DOIs returned before minting, but this has not been implemented.