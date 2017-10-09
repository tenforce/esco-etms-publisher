###
# DoUntilTransformer
# this transformer can be used to apply a transformation query to a graph until a validating query is fulfilled.
###
class Publisher::Transformers::DoUntilTransformer < Publisher::Transformers::Transformer
  ###
  # applies a transformation on the working graph until until_query returns false
  # @param do_query, the transformation to apply (typically a delete/insert query)
  # @param until_query, this should be a boolean query (eg ASK {})
  ##
  def transform(do_query, until_query)
    i = 0
    resources_to_transform = count(until_query)
    log.info "ask pattern matches in #{graph}: #{resources_to_transform}"
    while ask(until_query)
      client.update(%(
                    #{prefixes}
                           WITH <#{graph}>
                           #{do_query}
                    ))
      i += 1
      if i == 2 && count(until_query) == resources_to_transform
        log.info "ask pattern still matches #{resources_to_transform}, aborting after #{i} iterations"
        raise "invalid transformation"
      end
    end
    if i > 0
      log.info "transform completed after #{i} iterations"
    else
      log.info "ask query returned false immediately, transform no longer required?"
    end
  end

  def ask(until_query)
    client.query(%(
                 #{prefixes}
                         ASK { GRAPH <#{graph}> {
                          #{until_query}
                 }}
                 ))
  end

  def count(until_query)
    super(until_query)
  end
end
