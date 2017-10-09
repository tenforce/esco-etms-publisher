require 'fileutils'

###
# GraphToFileDumper
# dumps a graph to a ntriples file
###
class Publisher::GraphToFileDumper
  include Publisher::Helpers
  attr_reader :client, :prefixes

  def initialize(client, prefixes)
    @client = client
    @prefixes = prefixes
  end

  def dump(export_graph, path, batchsize)
    count = @client.query("SELECT (COUNT(*) AS ?count) FROM <#{export_graph}> WHERE { ?s ?p ?o}").first["count"].to_i
    log.info "dumping #{count} triples from #{export_graph} to #{path} using batchsize #{batchsize}"
    offset = 0
    FileUtils.touch(path)
    until offset > count
      result = @client.query(%(
      CONSTRUCT {?s ?p ?o }
      FROM <#{export_graph}>
      WHERE { ?s ?p ?o}
      LIMIT #{batchsize} OFFSET #{offset}), content_type: "text/plain")
      File.open(path, "a") do |file|
        RDF::NTriples::Writer.new(file, prefixes: prefixes) do |writer|
          writer << result
        end
      end
      offset += batchsize
      log.debug "dumping #{offset} to #{offset + batchsize}"
    end
  end
end
