FROM semtech/mu-ruby-template:2.3.0-ruby2.3
MAINTAINER Niels Vandekeybus <niels.vandekeybus@tenforce.com>
ENV PUBLISHER_EXPORT_PATH="/exports"
ENV MU_SPARQL_TIMEOUT=300
ENV CONFIG_DIR_PUBLISHER="/config"
