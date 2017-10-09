require "yaml"
require "thread"
require "zlib"

###
# FileGenerator
# runs exporters, transformers and finally generates a file on the resulting graph
###
class Publisher::FileGenerator
  include Publisher::Helpers

  EXPORT_MAP = YAML.load_file File.join(ENV["CONFIG_DIR_PUBLISHER"], "publisher.yml")
  TRANSFORMATIONS = YAML.load_file File.join(ENV["CONFIG_DIR_PUBLISHER"], "transformations.yml")
  SEMAPHORE = Mutex.new
  @@RUNNING = false

  attr_reader :export_graph, :application_graph, :id

  def initialize(id)
    @application_graph = graph
    @export_graph = publication_iri(id)
    @start = DateTime.now
    @id = id
  end

  def self.RUNNING
    @@RUNNING
  end

  def self.RUNNING=(bool)
    @@RUNNING = bool
  end

  def self.generate(id)
    gen = new(id)
    gen.generate
  end

  def self.cleanup_graph(id)
    client.update("DROP SILENT GRAPH <#{publication_iri(id)}>")

  end

  def types
    EXPORT_MAP[:types]
  end

  def prefixes
    EXPORT_MAP[:prefixes]
  end

  def languages
    EXPORT_MAP[:languages]
  end

  def sparql_prefixes
    prefixes.map { |prefix, value| "PREFIX #{prefix}: <#{value}>" }.join("\n")
  end

  def statements
    client.query("SELECT (COUNT(*) as ?count) FROM <#{export_graph}> WHERE {?s ?p ?o }").first["count"].value.to_i
  end

  def generate
    export_types
    apply_transformations
    generate_file
  end

  def export_types
    exporter = Publisher::Exporters::TypeExporter.new(client, application_graph, export_graph, sparql_prefixes)
    types.each do |type, config|
      log.info "exporting #{type}"
      exporter.export(type, normalize(config))
    end
    if languages && languages.size > 0
      exporter = Publisher::Exporters::LabelExporter.new(export_graph, languages)
      exporter.export
    end
  end

  def apply_transformations
    yaml = TRANSFORMATIONS
    prefixes = yaml[:prefixes].map { |prefix, value| "PREFIX #{prefix}: <#{value}>" }.join("\n")
    transformations = yaml[:transformations]
    transform = Publisher::Transformers::DoUntilTransformer.new(export_graph, prefixes)
    transformations[:do_until].each do |name, config|
      if config.key?(:query) && config.key?(:until)
        log.info "applying transformation #{name}"
        transform.transform(config[:query], config[:until])
      else
        log.info "ignored transformation #{name}, missing configuration"
      end
    end
    transform = Publisher::Transformers::NodeLiteralTransformer.new(export_graph, prefixes)
    transformations[:node_literal].each do |name, config|
      log.info "applying nodeliteral transformation #{name} for #{config[:class]} and prop #{config[:property]}"
      transform.transform(config[:class], config[:property])
    end

    transform = Publisher::Transformers::InverseCreator.new(export_graph, prefixes)
    transformations[:inverse].each do |name, config|
      log.info "applying inverse transformations #{name}}"
      transform.transform(config[:property], config[:inverse])
    end
  end

  def generate_file
    dumper = Publisher::GraphToFileDumper.new(client, prefixes)
    path = Publisher::Helpers::file_path_for(id)
    dumper.dump(export_graph, path, 5000)

    gzip_path = path + '.gz'
    Zlib::GzipWriter.open(gzip_path) do |gz|
      gz.mtime = File.mtime(path)
      gz.orig_name = path
      gz.write IO.binread(path)
    end
    path
  end

  ###
  # normalizes a type configuration
  # each property listed in the config is transformed to an object with attributes:
  #  - varname, to be used in the query for the value eg ?resource <property> ?var_name
  #  - uri, which is the property wrapped by <> if it's a uri or the property if it uses a prefix
  ###
  def normalize(config)
    c = { optional_properties: {}, required_properties: {}, additional_filter: config[:additional_filter] }
    i = 0
    [:optional_properties, :required_properties].each do |prop_type|
      config[prop_type].each do |prop|
        c[prop_type][prop] = {}
        c[prop_type][prop]["varname"] = "prop_#{prop_type[0..2]}_#{i}"
        i += 1
        c[prop_type][prop]["uri"] = prop.start_with?("http") ? "<#{prop}>" : prop
      end
    end
    c
  end
end
