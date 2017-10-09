module Publisher::WebHelpers
  def valid_json_message?(message)
    message.is_a?(Hash) && message.key?("data") && message["data"].is_a?(Hash) &&
        message["data"]["type"] == "publications" && message["data"]["attributes"].is_a?(Hash) &&
        message["data"]["attributes"].key?("name")
  end

  def json_api_wrap(data)
    link = data.is_a?(Array) ? "/publications" : "/publications/#{data.id}"
    JSON.dump({data: data, links: {"self": link}})
  end
end
