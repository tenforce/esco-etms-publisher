###
# InverseCreator
# given a property and it's inverse will create statements for the inverse
###
class Publisher::Transformers::InverseCreator < Publisher::Transformers::Transformer
  def transform(property, inverse)
    resources_to_transform(property).each do |uri|
      client.update(%(
      #{prefixes}
      WITH <#{graph}>
      INSERT  {
        ?val #{inverse} #{uri}
      }
      WHERE {
        #{uri} #{property} ?val
      }))
    end
  end

  def resources_to_transform(property)
    uris = []
    count = count("?resource #{property} ?value FILTER(isIRI(?value))")
    i = 0
    batchsize = 10_000
    until i > count
      result = client.query(%(
                            #{prefixes}
                            SELECT distinct ?resource
                            FROM <#{graph}>
                            WHERE {
                              ?resource #{property} ?value.
                              FILTER(isIRI(?value))
                            }
                            LIMIT #{batchsize}
                            OFFSET #{i}
                            ))
      uris += result.map { |r| "<#{r['resource'].value}>" }
      i += batchsize
    end
    uris
  end
end