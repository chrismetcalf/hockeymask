require "rubygems"
require "bundler/setup"
require "sinatra"
require "sinatra/json"
require "soda/client"
require "dalli"
require "rack-cache"

# Defined in ENV on Heroku. To try locally, start memcached and uncomment:
# ENV["MEMCACHE_SERVERS"] = "localhost"
if memcache_servers = (ENV["MEMCACHE_SERVERS"] || ENV["MEMCACHIER_SERVERS"] )
  use Rack::Cache,
    verbose: true,
    metastore:   "memcached://#{memcache_servers}",
    entitystore: "memcached://#{memcache_servers}"
end

class HockeyMask < Sinatra::Base
  helpers Sinatra::JSON

  before do
    @client = SODA::Client.new({
      :domain => ENV["DOMAIN"],
      :app_token => ENV["SOCRATA_APP_TOKEN"]
    })
  end


  get '/apis.json' do
    cache_control :public, max_age: 3600 # 60 mins.
    document = {
      "name" => "Socrata Open Government APIs",
      "description" => "This is an inventory of APIs available as Socrata Open Data APIs.",
      "image" => "http://dev.socrata.com/img/soda.png",
      "tags" => [
        "API",
        "government",
        "open data",
        "Socrata",
        "SODA"
      ],
      "created" => Time.now.strftime("%Y-%m-%d"),
      "modified" => Time.now.strftime("%Y-%m-%d"),
      "url" => request.url,
      "SpecificationVersion" => "0.14",
      "maintainers" => [
        {
          "FN" => "Chris Metcalf",
          "X-twitter" => "chrismetcalf",
          "email" => "chris.metcalf@socrata.com",
          "vCard" =>"http://chrismetcalf.net/work.vcf"
        }
      ]
    }

    # Fetch all of the domains that we want to add in as includes
    document["include"] = @client.get(ENV["DATASET_UID"]).collect { |site|
      {
        "name" => site["name"],
        "url" => "http://" + request.host + "/sites/" + site["domain"] + "/apis.json"
      }
    }

    json document
  end

  get '/sites/:domain/apis.json' do
    cache_control :public, max_age: 900 # 15 mins.
    site = @client.get("/resource/#{ENV["DATASET_UID"]}/#{params[:domain]}.json")

    document = {
      "name" => "#{site["name"]} APIs",
      "description" => "This is an inventory of APIs made available by #{site["name"]}",
      "image" => site["logo"],
      "tags" => (site["tags"] || "").split(/,\s*/),
      "created" => Time.now.strftime("%Y-%m-%d"),
      "modified" => Time.now.strftime("%Y-%m-%d"),
      "url" => request.url,
      "SpecificationVersion" => "0.14",
      "maintainers" => [
        {
          "email" => site["email"],
        }
      ]
    }

    # Fetch data.json and use it to form our API listing
    document["apis"] = SODA::Client.new({
      :domain => params[:domain],
      :app_token => ENV["SOCRATA_APP_TOKEN"]
    }).get("/data.json").reject {|d| d["identifier"] == "data.json" }.collect do |dataset|
      {
        "name" => dataset["title"],
        # "description" => CGI::escapeHTML(dataset["description"]),
        "description" => dataset["description"],
        "humanURL" => dataset["landingPage"],
        "baseURL" => "https://#{site["domain"]}/resource/#{dataset["identifier"]}",
        "tags" => dataset["keyword"],
        "properties" => [ {
            "type" => "X-Signup",
            "url" => "https://#{site["domain"]}/signup"
          }, {
            "type" => "X-Dev-Site",
            "url" => "http://dev.socrata.com",
          }, {
            "type" => "X-Foundry",
            "url" => "http://dev.socrata.com/foundry/#/#{site["domain"]}/#{dataset["identifier"]}"
          } ]
      }
    end

    json document
  end
end

run HockeyMask
