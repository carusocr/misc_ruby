#!/usr/bin/env ruby
# Script that accepts a keyword, looks for it on craigslist, emails me if there
# are any hits.
require 'mechanize'
require 'pony'

searchsite = 'http://philadelphia.craigslist.org/'
searchterm = ARGV[0] or abort "Must provide search term!\n"
agent = Mechanize.new
a = Array.new
agent.get(searchsite) do |page| 
	search_result = page.form_with(:id => 'search') do |search|
		search.query = searchterm
	end.submit
	search_result.root.children.xpath("//p").each do |link|
		a << link.text.gsub(/\n/,'').gsub(/\s+/,' ').gsub(/pic/,'').strip + "\n\t" + link.xpath('a').first.attributes['href'] + "\n\n"
	end
end
Pony.mail(:to => 'carusocr@ldc.upenn.edu', :from => 'craigseek@devbox', :subject => "#{searchterm} Search Results", :body => a)
