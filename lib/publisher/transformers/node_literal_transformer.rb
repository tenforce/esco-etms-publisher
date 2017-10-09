require 'securerandom'
###
# NodeLiteralTransformer
# this transformer can be used to change the literal value of a property to a NodeLiteral resource.
# the node literal has a esco:language property and a datatyped esco:nodeLiteral
# this makes no use of STRUUID() because it is broken in virtuoso
###
class Publisher::Transformers::NodeLiteralTransformer < Publisher::Transformers::Transformer
  def transform(klass, property)
    concept_uris = resources_to_transform(klass, property)
    log.info "#{concept_uris.size} resources match requirements"
    concept_uris.each do |uri|
      client.update(%(
                    #{prefixes}
                    WITH <#{graph}>
                    DELETE {
                      #{uri} #{property} ?description.
                    }
                    INSERT {
                      #{uri} #{property} ?nodeLiteral.
                      ?nodeLiteral a esco:NodeLiteral;
                          esco:language ?language;
                          esco:nodeLiteral ?newDescription.
                    }
                    WHERE {
                      #{uri} #{property} ?description;
                                a #{klass}.
                      BIND(STRDT(STR(?description),xsd:string) as ?newDescription).
                      BIND(LANG(?description) as ?language).
                      BIND(<http://data.europa.eu/esco/node-literal/#{SecureRandom.uuid}> as ?nodeLiteral)                      
                      FILTER(isLiteral(?description))
                    }
      ))
    end
  end

  def resources_to_transform(klass, property)
    uris = []
    count = count(klass, property)
    i = 0
    batchsize = 10_000
    until i > count
      result = client.query(%(
                            #{prefixes}
                            SELECT distinct ?resource
                            FROM <#{graph}>
                            WHERE {
                              ?resource a #{klass}; #{property} ?prop.
                            }
                            LIMIT #{batchsize}
                            OFFSET #{i}
                            ))
      uris += result.map { |r| "<#{r['resource'].value}>" }
      i += batchsize
    end
    uris
  end

  def count(klass, property)
    super("?resource a #{klass}; #{property} ?prop.")
  end
end
