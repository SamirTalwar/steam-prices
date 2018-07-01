#!/usr/bin/env ruby
# encoding=utf-8

require 'date'
require 'nokogiri'
require (ARGV[0] == '--fake') ? './fake-scraperwiki' : 'scraperwiki'
require 'typhoeus'

$start = Time.now.to_date

COUNTRIES = ['uk', 'us', 'fr']
REMOVE = /[\uFFFD®™]/
CURRENCIES = /[$£€]/

PRICE_REGEX = /#{CURRENCIES}[0-9.,]+|[0-9.,]+#{CURRENCIES}|Free to Play/i

BATCH_SIZE = 10

def games_and_prices_from response, country
  document = Nokogiri::HTML response.body.encode('utf-8', 'utf-8', :invalid => :replace)

  document.css('.search_result_row').collect { |row|
    id = /^https:\/\/[^\/]+\/app\/(\d+)/.match(row['href'])[1].to_i
    name = row.at_css('.search_name .title').text.gsub(REMOVE, '').strip
    release_date = Date.parse(row.at_css('.search_released').text.strip) rescue nil
    prices = row.at_css('.search_price').text.strip
    original_price, discounted_price = (/(#{PRICE_REGEX})? *(#{PRICE_REGEX})?/.match(prices)).captures.collect { |price|
      if price.nil?
        nil
      elsif price =~ /Free to Play/i
        0
      else
        price.strip.gsub(CURRENCIES, '').sub(',', '.').to_f
      end
    }
    original_price ||= 0

    {
      id: id,
      country: country,
      name: name,
      release_date: release_date,
      original_price: original_price,
      discounted_price: discounted_price
    }
  }
end

def save games, prices, tries = 3
  begin
    ScraperWiki::save_sqlite [:id, :country], games, 'games'
    ScraperWiki::save_sqlite [:id, :country, :date], prices, 'prices'
  rescue SQLite3::BusyException
    if tries > 1
      puts 'SQLite3 was busy. Trying again in 10 seconds...'
      sleep 10
      save games, prices, (tries - 1)
    else
      raise
    end
  end
end

requests = COUNTRIES.flat_map do |country|
  html = Typhoeus::Request.get("https://store.steampowered.com/search/?cc=#{country}&category1=998").body
  html.encode! 'utf-8', 'utf-8', :invalid => :replace
  document = Nokogiri::HTML html
  page_count = document.css('.search_pagination_right a').map(&:text).map(&:to_i).max
  puts "#{country} has #{page_count} pages."

  (1..page_count).collect { |page|
    request = Typhoeus::Request.new "https://store.steampowered.com/search/?cc=#{country}&category1=998&page=#{page}"
    [request, country]
  }
end

hydra = Typhoeus::Hydra.new max_concurrency: 5
batch_no = 0
requests.each_slice(BATCH_SIZE) do |batch|
  batch_no += 1
  puts "Batch #{batch_no} running..."
  batch.each do |request, country|
    hydra.queue request
  end
  hydra.run

  responses = batch.flat_map { |request, country|
    games_and_prices_from request.response, country
  }

  games = responses.collect { |response|
    {
      id: response[:id],
      country: response[:country],
      name: response[:name],
      release_date: response[:release_date]
    }
  }
  prices = responses.collect { |response|
    {
      id: response[:id],
      country: response[:country],
      date: $start,
      original_price: response[:original_price],
      discounted_price: response[:discounted_price]
    }
  }

  save games, prices
end

puts 'Done.'
