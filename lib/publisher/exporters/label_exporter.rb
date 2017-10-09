class Publisher::Exporters::LabelExporter
  include  Publisher::Helpers
  attr_reader :application_graph, :export_graph, :languages
  def initialize(export_graph, languages)
    @application_graph = graph
    @export_graph = export_graph
    @languages = languages
  end

  def export
    concept_uris = retrieve_label_uris
    batch_size = 200
    threshold = 0.2
    i = 0
    log.info "#{concept_uris.size} labels match requirements"
    while i < concept_uris.size && !concept_uris.empty?
      n = i + batch_size > concept_uris.size ? concept_uris.size : i + batch_size
      uris = concept_uris[i..n]
      client.update(%(
                    #{sparql_prefixes}
                      INSERT {
                        GRAPH <#{export_graph}> {
                            ?label a skosxl:Label;
                                skosxl:literalForm ?form.
                            ?label esco:hasLabelRole ?role.
                        }
                      }
                      WHERE {
                         GRAPH <#{application_graph}> {
                            ?label a skosxl:Label;
                                skosxl:literalForm ?form.
                            OPTIONAL { ?label esco:hasLabelRole ?role }
                         }
                      FILTER(?label IN (#{uris.join(',')}))
                      }
      ))
      i = n
      if n / concept_uris.size.to_f >= threshold
        log.info "inserted #{(n / concept_uris.size.to_f * 100).round(1) }% of labels"
        threshold += 0.2
      end
    end
  end

  ###
  # retrieves the uri's of each label uris
  ###
  def retrieve_label_uris
    uris = []
    i = 0
    total = count
    batchsize = 10_000
    until i > total
      result = client.query(%(
                            #{sparql_prefixes}
                            SELECT distinct ?label
                            WHERE {
                              #{where_statements}
                            }
                            LIMIT #{batchsize}
                            OFFSET #{i}
                            ))
      uris += result.map { |r| "<#{r['label'].value}>" }
      i += batchsize
    end
    uris
  end

  def count
    client.query(%(
                     #{sparql_prefixes}
                     SELECT (count(distinct(?label)) as ?count)
                     WHERE {
                       #{where_statements}
                     }
                 )).first["count"].value.to_i
  end

  def sparql_prefixes
    %(
    PREFIX skosxl: <http://www.w3.org/2008/05/skos-xl#>
    PREFIX esco:   <http://data.europa.eu/esco/model#>
    )
  end

  def where_statements
    %(
    GRAPH <#{export_graph}> {
        ?concept ?labelPred ?label.
        FILTER(?labelPred in (skosxl:prefLabel, skosxl:altLabel, skosxl:hiddenLabel))
    }
    GRAPH <#{application_graph}> {
        ?label skosxl:literalForm ?form
    BIND(LANG(?form) as ?lang)
    FILTER(?lang in (#{languages.map{|l| "\"#{l}\""}.join(',')}))
    })
  end
end