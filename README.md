# esco publisher

This project provides a microservice to create an esco publication. It is intented to run as part of the ETMS system.

## Usage
```
docker build -t esco/publisher .
docker run -p 80:80 --volume /your/config/dir:/config --volume /your/export/dir:/exports -e SPARQL_ENDPOINT=http://yourendpoint:8890/sparql esco/publisher
```

### configuration
Create the appropriate configuration in /config/publisher.yml and config/transformations.yml. See `config/publisher.yml.example` and `config/transformations.yml.example`. 
You can also provide the following environment variables to configure this service

* `SPARQL_ENDPOINT`  SPARQL read endpoint URL. Default: http://database:8890/sparql (the triple store should be linked as database to the microservice).

* `MU_APPLICATION_GRAPH` configuration of the graph to be used for publishing (eg where your data lives) http://mu.semte.ch/application.

* `MU_SPARQL_TIMEOUT` timeout (in seconds) for SPARQL queries. Default: 300 seconds.

* `PUBLISHER_EXPORT_PATH` path were exports are stored, default /exports

## Development

```
docker run -v `pwd`/the-data:/data -e SPARQL_UPDATE=true -p 8890 --name inspiring_bartik -d tenforce/virtuoso
docker run --link inspiring_bartik:database -p 8000:80 -v `pwd`:/app -v `pwd`/exports:/exports \
           -e RACK_ENV=development -e MU_SPARQL_TIMEOUT=300 -e PUBLISHER_EXPORT_PATH=/exports -d semtech/mu-ruby-template:2.3.0-ruby2.3
```


