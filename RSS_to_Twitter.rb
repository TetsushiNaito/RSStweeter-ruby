#!/opt/rbenv/shims/ruby
# rewrite shebang to appropriate path
# test fot git

require "time"
require "rss"
require "json"
require "sanitize"
require "twitter"

# RSS processing class
class RSS_to_tweet
  def initialize( url, timestamp )
    @url = url
    @timestamp = timestamp
    @timestamp_now = Time.parse( '2001-01-01 00:00:00 JST' ) # あくまで初期化
    
    # RSS取得
    begin
      if not ( @rss = RSS::Parser.parse( @url ) )
        puts "caution: cannot parse RSS \"#{@url}\"\n"
      end
    rescue RSS::InvalidRSSError
      @rss = RSS::Parser.parse( @url, false )
    end
 
    # confirm newest timestamp
    # if failed to parse, set it to now
    begin
      @lasttime = Time.parse( @timestamp )
    rescue ArgumentError
      puts "caution: cannot parse timestamp \"#{@timestamp}\" for #{@url}\n"
      puts "set time to now.\n"
      @lasttime = Time.now
    end
  end

  attr_accessor :timestamp_now

  def to_tweet
    tweet = []
    case @rss.class.to_s
    # in case of RSS 1.0
    when "RSS::RDF" then
      @rss.items.each do |item|
        if not item.dc_date then item.dc_date = Time.parse( '2001-01-01 00:00:00 JST' ) end
      end
      rss_array = @rss.items.sort_by{|item| item.dc_date}.reverse
      @timestamp_now = rss_array[0].dc_date
      if @timestamp_now > @lasttime then
        rss_array.each do |item|
          if item.dc_date > @lasttime then
            tweet.unshift( make_text( item.title, item.description, item.link ) )
          end
        end
      else
        @timestamp_now = @lasttime
      end
    # in case of RSS 0.9x/2.0
    when "RSS::Rss" then
      @rss.channel.items.each do |item|
        if not item.date then item.date = Time.parse( '2001-01-01 00:00:00 JST' ) end
      end
      rss_array = @rss.channel.items.sort_by{|item| item.date}.reverse
      @timestamp_now = rss_array[0].date
      if @timestamp_now > @lasttime then
        rss_array.each do |item|
          if item.date > @lasttime then
            tweet.unshift( make_text( item.title, item.description, item.link ) )
          end
        end
      else
        @timestamp_now = @lasttime
      end
    # in case of Atom
    when "RSS::Atom::Feed" then
      @rss.entries.each do |item|
        if not item.updated.content then item.updated.content = Time.parse( '2001-01-01 00:00:00 JST' ) end
      end
      rss_array = @rss.entries.sort_by{|item| item.updated.content}.reverse
      @timestamp_now = rss_array[0].updated.content
      if @timestamp_now > @lasttime then
        rss_array.each do |item|
          if item.updated.content > @lasttime then
            tweet.unshift( make_text( item.title.content, item.content.content, item.link.href ) )
          end
        end
      else
        @timestamp_now = @lasttime
      end
    # unknown...?
    else
      puts "Unknown RSS Type \"#{@url}\"\n"
    end
    return tweet
  end
  
  # make text to tweet
  private
  def make_text( title, description, link )
    # descriptionからHTMLタグを抜く
    description = Sanitize.clean( description )
    text = "#{title}\n#{description}"
    if text.length > 115 
      text = text[0, 112] + "..."
    end
    return "#{text}\n#{link}"
  end
  
# end of class
end

# open a JSON file for RSS configuration
# make it named as "rss_info.json" at same directory of this script
# format of JSON is :
# {
#   "URL1":"TimeStamp1",
#   "URL2":"TimeStamp2"
# }

jsonfile = File.dirname(__FILE__) + "/rss_info.json"
if ( ! File.exist?( jsonfile ) || File.zero?( jsonfile ) )
  puts "JSON file #{jsonfile} not found or empty."
  exit!
end
f = File.open( jsonfile )
begin
  rsslist = JSON.load( f )
rescue JSON::ParserError
  f.close
  puts "cannot parse JSON file. please check syntax.\n"
  exit!
end
f.close

# process by each URL of RSS
t_array = []
rsslist.keys.each do |url|
  # make instance of RSS processing class
  rss = RSS_to_tweet.new( url, rsslist[url] )

  # push array of tweets
  t_array.push( rss.to_tweet )

  # update newest timestamp of RSS
  rsslist[url] = rss.timestamp_now
end

# do tweet
client = Twitter::REST::Client.new do |config|
  config.consumer_key        = "your Consumer Key (API Key)"
  config.consumer_secret     = "your Consumer Secret (API Secret)"
  config.access_token        = "your Access Token"
  config.access_token_secret = "your Access Token Secret"
end
t_array.each do |tweets|
  tweets.each do |tweet|
    client.update( tweet )
    sleep 10
  end
end

# update JSON file
jsontxt = JSON.pretty_generate( rsslist )
File.open( jsonfile, "w" ) do |f|
  f.write( jsontxt )
end

# the end.
