#!/usr/bin/ruby
# encoding: UTF-8

# PokerScout Scraper
# Scrapes traffic data off of PokerScout.com and writes it out to a CSV file.


require 'optparse'
require 'selenium-webdriver'
require 'time'


test_file_path = 'test_page/Online%20Poker%20Traffic%20Rankings%20&%20News%20_%20Poker%20Sites%20&%20Networks%20_%20PokerScout.html'
test_url = "file://#{File.join(Dir.pwd, test_file_path)}"
prod_url = 'http://www.pokerscout.com/'


options = {}
option_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: scout_scraper.rb [options]'

  opts.on('-h', '--help', 'Print this help screen') do
    puts opts
    exit
  end

  options[:output_dir] = File.join(Dir.pwd, 'output')
  opts.on('-d', '--output-dir DIR', 'Output directory') do |dir|
    if Dir.exists?(dir)
      options[:output_dir] = dir
      options[:output_path] = File.join(options[:output_dir], options[:output_filename])
    else
      puts "#{dir} does not exist; saving to #{options[:output_dir]}"
    end
  end

  options[:output_filename] = "stats_#{Time.now.to_i}.csv"
  opts.on('-f', '--output-filename FILE', 'Output filename') do |file|
    options[:output_filename] = file
    options[:output_path] = File.join(options[:output_dir], options[:output_filename])
  end

  options[:use_live_data] = true
  opts.on('-t', '--test', 'Scrape test file, not live data') do
    options[:use_live_data] = false
  end

  options[:output_path] = File.join(options[:output_dir], options[:output_filename])
end
option_parser.parse!


# XPath for the table rows containing poker stats (and column names)
trs_tds_xpath = "//div[contains(@class,'topbrown')]//td[contains(.,'Online Poker Traffic Report')]/../../../../../..//%s[10]/.."
@trs_xpath = trs_tds_xpath.sub('%s', 'td')    # all the <tr>s containing a row of traffic data
@header_xpath = trs_tds_xpath.sub('%s', 'th') # the <tr> containing the column names


# Gets the column names (i.e. Rank, Site/Network). Changes column names to something readable.
# Returns an array of column names.
def get_column_names
  column_names_tr = @browser.find_element :xpath, @header_xpath
  column_names_ths = column_names_tr.find_elements :tag_name, 'th'
  
  column_names = []
  column_names_ths.each do |th|
    column_names.push th.text
  end

  column_names.map! do |name|
    case name
    when ''
      name = 'Is Network'
    when '#'
      name = 'Rank'
    when 'US'
      name = 'Allows US Players'
    when 'Data'
      name = 'Is Data Current'
    end

    name.match(/\W/) ? "\"#{name}\"" : name
  end

  column_names
end


# Pull the traffic data out of a <tr>. Returns an array of traffic data.
def get_data_from_tr(tr)
  row = []
  
  tds = tr.find_elements :tag_name, 'td'
  tds.each_with_index do |td, i|
    text = td.text

    case i
    when 1  # Is network?
      img = td.find_elements :tag_name, 'img'
      text = img.length > 0
    when 2  # Fix text in Site/Network column
      text.sub! /\s*[•*]\W+reviews.*$/, ''
    when 3  # Are US players allowed?
      imgs = td.find_elements :tag_name, 'img'
      if(imgs.length > 0)
        alt = imgs[0].attribute('alt')
        case alt
        when 'Y', 'y'
          text = true
        when 'N', 'n'
          text = false
        end
      end
    when 5  # Is Data Current?
      imgs = td.find_elements :tag_name, 'img'
      if(imgs.length > 0)
        title = imgs[0].attribute('title')
        text = !(title =~ /not/)
      end
    end

    row.push text
  end

  row
end


# Get the traffic data out of every <tr>. Returns an array of arrays of traffic data.
def get_stats_from_rows
  trs = @browser.find_elements :xpath, @trs_xpath
  stats = []

  trs.each do |tr|
    stats.push get_data_from_tr(tr)
  end

  stats
end


at_exit do  # Make sure the browser closes if the script crashes
  @browser.close unless @browser.nil?
end


time_start = Time.now
puts "Writing data to #{options[:output_path]}"

url_to_scrape = options[:use_live_data] ? prod_url : test_url
puts "Getting traffic data from #{url_to_scrape}"

@browser = Selenium::WebDriver.for :firefox
@browser.get url_to_scrape

# Page should be loaded. Scrape the data
column_names = get_column_names
stats_rows = get_stats_from_rows

# Write the data to the output file
File.open(options[:output_path], 'w') do |file|
  file.puts column_names.join(',')
  stats_rows.each do |row|
    file.puts row.join(',')
  end
end

time_end = Time.now
puts "Scraping complete in #{(time_end - time_start).round(2)}s"
