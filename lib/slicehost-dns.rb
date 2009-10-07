#! /usr/bin/env ruby

require 'rubygems'
require 'activeresource'
require 'yaml'
require 'logger'

# Override the logger output to show just the messgae
class Logger
  class Formatter
    def call(severity, time, progname, msg)
      "#{msg}\n"
      # FIXME: exit on fatal messages
    end
  end
end

# Global logger and verbosity level
$LOG = Logger.new($stdout)
if ARGV.delete('--verbose')
  $LOG.level = Logger::DEBUG
else
  $LOG.level = Logger::INFO
end

# Example yaml
if ARGV.include? '--example'
  example = File.dirname(__FILE__) + '/example.yml'
  puts open(example).read 
  exit
end

# Help text
if ARGV.empty? or ARGV.delete('--help')
  $LOG.fatal("Usage: slicehost-dns (--dump --dry --verbose --help) [config.yml]")
  exit
end

dump = ARGV.delete('--dump')
dry_run = ARGV.delete('--dry')
filename = ARGV.shift
config = {}
templates = {}

# In Dump mode, if there's a filename and it exists, rewrite it. If there's a
# filename and it doesn't exist, dump to it. If there's no filename, dump to
# stdout.

if filename and FileTest.exists?(filename)
  config = YAML.load_file(filename)
  $LOG.debug(YAML.dump(config))
  # Drop the templates section, since we're using it just to generate anchors
  # and the YAML parser does all the work.
  templates = config.delete('templates')
elsif dump and not filename
  filename = "-"
elsif not dump
  raise ArgumentError, "no filename provided"
end

# Prefer the api key from the configuration file
if config.has_key?('api')
  API = config.delete('api')
  $LOG.info("Using API key from YAML file: #{API}") if not API.nil?
else
  API = ENV['SLICEHOST_API_KEY']
  $LOG.info("Using API key from environment: #{API}") if not API.nil?
end
raise ArgumentError, "no API key found" if API.nil?

$:.unshift File.dirname(__FILE__)
require 'zone'
require 'record'
require 'reconciler'

Zone.site = "https://#{API}@api.slicehost.com/"
Record.site = "https://#{API}@api.slicehost.com/"

zones = Zone.find :all
records = Record.find :all

if dry_run
  class Zone
    def save
      $LOG.debug("~> dry saving zone #{origin}")
    end
    def destroy
      $LOG.debug("~> dry destroying zone #{origin}")
    end
  end
  class Record
    def save
      $LOG.debug("~> dry saving record #{kind} #{name}: #{data}")
    end
    def destroy
      $LOG.debug("~> dry destroying record #{kind} #{name}: #{data}")
    end
  end
end

if dump
  output = {}
  output['api'] = API
  
  zones.each do |zone|
    local, records = records.partition {|r| r.zone_id == zone.id }
    
    primary_a = local.detect {|r| r.a? && r.name == zone.origin }
    local.delete(primary_a)
    ip = primary_a.data
    
    wildcard = local.detect {|r| r.a? && (r.name == "*" || r.name == "*.#{zone.origin}")}
    local.delete(wildcard)
    
    domain = {}
    
    google = false
    
    local.each do |record|
      case record.kind
      when 'ns'
      when 'srv'
        domain['srv'] ||= {}
        domain['srv'][record.name] ||= {}
        domain['srv'][record.name][record.data] = record.aux
        google = true if record.data.match(/xmpp-server\d?\.l\.google/)
      when 'mx'
        domain['mx'] ||= {}
        domain['mx'][record.data] = record.aux
        google = 'mail' if record.data.match(/google/i) && ! google
      when 'txt'
        domain['txt'] ||= []
        domain['txt'] << record.data
      else
        domain[record.kind] ||= {}
        domain[record.kind][record.name] = record.data == ip ? 'this' : record.data
      end
    end
    
    if google
      domain['goog'] = google
      domain.delete('mx')
      unless google == 'mail'
        domain['srv'].delete("_xmpp-server._tcp.#{zone.origin}")
        domain['srv'].delete("_jabber._tcp.#{zone.origin}")
        domain['srv'].delete("_xmpp-client._tcp.#{zone.origin}")
        domain.delete('srv') if domain['srv'].empty?
      end
      # fuck it, we'll leave the spf record in there.
    end
    
    if domain['mx'] && domain['mx'].size == 1
      domain['mx'] = domain['mx'].keys.first
    end
    
    output[ip] ||= {}
    output[ip][zone.domain] = domain
  end
  
  if filename == "-"
    YAML.dump(output, $stdout)
  else
    File.open(filename, 'w') {|f| YAML.dump(output, f) }
  end
else
  config.each_pair do |ip, domains|
    unless ip.match(/(\d+\.){3}\d+/)
      $LOG.warn "\n~ skipping key #{ip}, not a valid ip address"
      next
    end
    domains.each_pair do |domain, desired_records|
      using_template = false
      if desired_records.nil?
        if templates.has_key?(ip)
          # There's no deep copy in Ruby, so we do this horrific thing
          desired_records = Marshal::load(Marshal.dump(templates[ip]))
          using_template = true
        else
          $LOG.warn("\ndomain #{domain}: No records, skipping ")
          next
        end
      end
      $LOG.info "\ndomain #{domain}:" unless using_template
      $LOG.info "\ndomain #{domain} using template for #{ip}:" if using_template
      zone = zones.detect {|z| z.domain == domain } || Zone.create_for_domain(domain)
      records_for_domain, records = records.partition {|r| r.zone_id == zone.id }
      # TODO: Separate out the reconciler from the processor, so that we
      # can do something nice here like saying, "No changes for this domain".
      Reconciler.new(zone, ip, records_for_domain, desired_records).process!
      zones.delete(zone)
    end
    leftovers = zones.map{|z| z.domain}.join(', ') unless zones.empty?
    puts "\n\ni'd delete #{leftovers} now but you'd hate me." if leftovers
    # TODO: let's enable deletes with this syntax in the YAML file:
    # ip:
    #   domain: { delete: 1 }
  end
end
