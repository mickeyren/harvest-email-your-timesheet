#!/usr/bin/env ruby

require 'rubygems'
require 'erb'
require 'harvested'
require 'pony'

load 'settings.rb'

def Time.yesterday
  now - 86400 
end

def Time.at_beginning_of_month
  this_month = Date.today
  parse("#{this_month.year}-#{this_month.month}-01")
end

def Time.at_beginning_of_last_month
  last_month = Date.today << 1
  parse("#{last_month.year}-#{last_month.month}-01")
end

# connect to the user's harvest account
puts 'Connecting to harvest...'
harvest = Harvest.client(Settings.harvest[:subdomain], Settings.harvest[:username], Settings.harvest[:password], :ssl => false) 

# fetch a particular client
puts 'Fetching information for client: ' + Settings.client_name

begin
  client = harvest.clients.all.find {|c| c.name == Settings.client_name }
rescue
  puts '   Error: Unable to find client name. Did you correctly set the credentials for connecting to Harvest?'
  exit
end

if !client
  puts '   Error: Unable to find client name. Did you correctly set the client name in the settings.rb file?'
  exit
end

# fetch all projects for this client
puts 'Now generating timesheet...'
projects = harvest.projects.all.select {|p| p.client_id == client.id }

# get all time entries for this project and put in one array
all_entries = Array.new
summaries = Hash.new
total_hours = 0
total_amount = 0.0

projects.each do |project|
  entries = harvest.reports.time_by_project(project, Time.at_beginning_of_last_month, Time.now)
  summaries[project.name] = Hash.new
  summaries[project.name]['hourly_rate'] = project.hourly_rate.to_f  
  summaries[project.name]["#{Time.at_beginning_of_last_month.year}-#{Time.at_beginning_of_last_month.month}"] = 0.0
  summaries[project.name]["#{Time.now.year}-#{Time.now.month}"] = 0  
  
  entries.each do |entry|
    entry['project'] = project
    entry['amount'] = project.hourly_rate.to_f * entry.hours.to_f
    all_entries << entry  
    total_hours += entry.hours.to_f
    total_amount += (project.hourly_rate.to_f * entry.hours.to_f)
    
    summaries[project.name]["#{Time.parse(entry.created_at).year}-#{Time.parse(entry.created_at).month}"] += entry.hours.to_f    
  end
    
end

puts summaries

# sort by date descending
all_entries.sort! { |b,a| a.created_at <=> b.created_at }

all_entries.select{ |k, v| Time.parse(k.created_at).month == Time.now.month }
 
# assemble html
puts 'Assembling html. Using stylesheet: ' + Settings.stylesheet
style = File.read(Settings.stylesheet)
content = File.read('email.erb')
html = ERB.new(content).result

# Uncomment if you want to dump the html in a file
# File.open("email.htm", 'w') { |f| f.puts(html) }

puts 'Sending email to ' + Settings.mail_recipient
begin
  Pony.mail(:to => Settings.mail_recipient, :subject => Settings.mail_subject, :html_body => html, :via => :smtp, :via_options => Settings.mail_options )
rescue
  puts '   Error: Unable to send email. Did you correctly set your mail settings?'
  exit
end

puts '...and Success! We are done.'