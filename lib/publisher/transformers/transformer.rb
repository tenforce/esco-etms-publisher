###
# Transformer
# abstract base class
###
class Publisher::Transformers::Transformer
  include Publisher::Helpers

  attr_reader :graph, :prefixes

  def initialize(work_graph, prefixes)
    @graph = work_graph
    @prefixes = prefixes
  end

  ###
  # counts distinct ?resource matching the where pattern
  # @param where_pattern
  ###
  def count(where_pattern)
    client.query("#{prefixes} SELECT (COUNT(distinct(?resource)) as ?count) FROM <#{graph}> WHERE { #{where_pattern} }").first["count"].value.to_i
  end
end
