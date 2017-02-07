#!/opt/rbenv/shims/ruby
# ↑shebangは適宜パスを書き換えること

require "time"
require "rss"
require "json"
require "sanitize"
require "twitter"

# RSS処理クラス
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
 
    # 最新のタイムスタンプを確認
    # パースできなかった場合は現在の時刻を設定する
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
    # RSSの種類ごとに処理を変える
    case @rss.class.to_s
    # RSS 1.0の場合
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
    # RSS 0.9x/2.0の場合
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
    # Atomの場合
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
    # 該当しない？
    else
      puts "Unknown RSS Type \"#{@url}\"\n"
    end
    return tweet
  end
  
  # ツイート内容を整形する
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
  
# クラス定義終わり
end

# RSS設定用JSONファイルを開く
# このスクリプトと同じディレクトリに
# 「rss_info.json」というファイル名で作っておくこと
# JSONの形式
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

# RSSのURLごとに処理
t_array = []
rsslist.keys.each do |url|
  # RSS処理クラスのインスタンス生成
  rss = RSS_to_tweet.new( url, rsslist[url] )

  # ツイートの配列をpushする
  t_array.push( rss.to_tweet )

  # RSSの最新タイムスタンプを更新
  rsslist[url] = rss.timestamp_now
end

# ツイート実行
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

# JSONファイルを更新
jsontxt = JSON.pretty_generate( rsslist )
File.open( jsonfile, "w" ) do |f|
  f.write( jsontxt )
end

# おしまい。
