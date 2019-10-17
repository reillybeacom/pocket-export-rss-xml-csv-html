require "sinatra"
require "sinatra/reloader"
require "csv"
require "builder"
require "./lib/pocket-ruby.rb"

enable :sessions

CALLBACK_URL = "http://localhost:4567/oauth/callback"

Pocket.configure do |config|
  config.consumer_key = '88132-f0195d4f284534d94979c60a'
end

get '/reset' do
  puts "GET /reset"
  session.clear
end

get "/" do
  puts "GET /"
  puts "session: #{session}"

  if session[:access_token]
    '
<h1>Export</h1>
<a href="/pocket_export.html">HTML</a>
|
<a href="/pocket_export_rss.xml">RSS</a>
|
<a href="/pocket_export.csv">CSV</a>
    '
  else
    '<a href="/oauth/connect">Connect with Pocket</a>'
  end
end

get "/oauth/connect" do
  puts "OAUTH CONNECT"
  session[:code] = Pocket.get_code(:redirect_uri => CALLBACK_URL)
  new_url = Pocket.authorize_url(:code => session[:code], :redirect_uri => CALLBACK_URL)
  puts "new_url: #{new_url}"
  puts "session: #{session}"
  redirect new_url
end

get "/oauth/callback" do
  puts "OAUTH CALLBACK"
  puts "request.url: #{request.url}"
  puts "request.body: #{request.body.read}"
  result = Pocket.get_result(session[:code], :redirect_uri => CALLBACK_URL)
  session[:access_token] = result['access_token']
  puts result['access_token']
  puts result['username']	
  # Alternative method to get the access token directly
  #session[:access_token] = Pocket.get_access_token(session[:code])
  puts session[:access_token]
  puts "session: #{session}"
  redirect "/"
end

def get_all_data
  client = Pocket.client(access_token: session[:access_token])
  @data = client.retrieve(detailType: :complete, sort: :newest, state: :all)['list']
end

get "/pocket_export.html" do
  content_type 'text/html'
  get_all_data
  erb :export_html
end
  
get "/pocket_export.csv" do
  content_type 'text/plain'
  get_all_data
  keys = %w(time_added status favorite is_article has_video given_url tags resolved_title excerpt)
  CSV.generate do |csv|
    csv << ['date'] + keys
    @data.each do |id, item|
      item['tags'] = item['tags'].keys.join(',') rescue ''
      csv << [Time.at(item['time_added'].to_i).strftime('%Y-%m-%d')] + item.slice(*keys).values
    end
  end
end

get "/pocket_export_rss.xml" do
  content_type 'text/plain'
  get_all_data

  @output = ""
  
  xml = Builder::XmlMarkup.new(:target => @output, :indent => 4)

  xml.rss version: "2.0" do
    xml.channel do
      xml.pubDate Time.now.rfc822
      xml.lastBuildDate Time.now.rfc822
      xml.link "https://app.getpocket.com/"
      xml.title "Pocket Export"
      xml.description "Pocket Export"
      @data.each do |id, item|
        xml.item do
          time =  Time.at(item['time_added'].to_i)
          xml.pubDate time.rfc822
          xml.guid(item['given_url'])
          xml.title item['given_title'] != "" ? item['given_title'] : item['resolved_title']
          xml.description item['excerpt']
          xml.link item['given_url']
          (item['tags'].keys rescue []).each do |tag|
            xml.category tag
          end
        end
      end
    end
  end

  @output
end
