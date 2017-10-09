require_relative "lib/publisher"

helpers Publisher::WebHelpers

configure do
  unless Publisher::FileGenerator.RUNNING
    Publisher::Helpers.wait_for_database
    Publisher::Publication.remove_old_running_publications
  end
end

before do
  content_type "application/vnd.api+json"
end

###
# retrieve a list of publications
###
get "/publications/" do
  json_api_wrap Publisher::Publication.list # todo pagination
end

###
# create a publication
###
post "/publications/" do
  begin
    request.body.rewind
    json_body = JSON.parse request.body.read
  rescue StandardError => e
    log.error e.message
    error("failed to parse message")
  end
  unless valid_json_message?(json_body)
    # invalid json message
    error("invalid jsonapi message")
    return
  end

  unless !Publisher::FileGenerator.RUNNING && Publisher::FileGenerator::SEMAPHORE.try_lock
    # publisher is already running or could not get mutex lock, so it will soon be running
    error("the creation of another publication is already running.", 503)
    return
  end

  # we"ve acquired the lock and have a valid json message
  Publisher::FileGenerator.RUNNING = true
  begin
    json_message = json_body["data"]
    attr = json_message.delete("attributes")
    json_message = json_message.merge(attr)
    publication = Publisher::Publication.create(name: json_message["name"], issued: json_message["issued"])
    publication.generate_file
    status 201
    json_api_wrap publication
  rescue StandardError => e
    log.error e.message
    log.debug e.backtrace
    Publisher::FileGenerator.RUNNING = false
    error("server error", 500)
  ensure
    Publisher::FileGenerator::SEMAPHORE.unlock
  end
end

###
# retrieve a publication
###
get "/publications/:id" do
  publication = Publisher::Publication.find(params[:id])
  json_api_wrap publication
end

###
# remove a publication
###
delete "/publications/:id" do
  publication = Publisher::Publication.find(params[:id])
  if publication.official?
    error("can't delete an official publication", 400)
  else
    if publication.status == "done" && publication.filename
        File.delete(Publisher::Helpers::file_path_for(publication.id))
    end
    publication.delete!
    status 204
  end
end

get "/publications/:id/download" do
  content_type "text/plain"
  publication = Publisher::Publication.find(params[:id])
  file = publication.filename

  if params[:gzip]
    content_type "application/octet-stream"
    file = file + ".gz"
  end
  send_file file
end

###
# mark a publication as official
# this will add the necessary metadata in the triple store and prevent deletion of the publication
# TODO: extract to separate service
###
post "/publications/:id/make-official" do
  publication = Publisher::Publication.find(params[:id])
  if publication && publication.status == "done"
    publication.status = "official"
    publication.persist!
    Publisher::PubOfficializer.new(publication).update_published
    status 200
    json_api_wrap publication
  else
    error("can only mark a publication official if it's done", 400)
  end
end

###
# return the version of the publisher microservice
###
get "/publications/version" do
  content_type "text/html"
  return Publisher::VERSION
end

###
# return the state of the generator
###
get "/publications/status" do
  json_api_wrap(running: Publisher::FileGenerator.RUNNING)
end

