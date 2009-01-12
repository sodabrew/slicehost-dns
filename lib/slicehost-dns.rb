#! /usr/bin/env ruby

require 'rubygems'
require 'activeresource'
require 'yaml'
require 'logger'

class Logger
  class Formatter
    def call(severity, time, progname, msg)
      "#{msg}\n"
    end
  end
end

# yes globals are evil but hey, i welcome patches. 
# and, a riddle: what are singletons except globals reduced to a pattern?
$LOG = Logger.new($stdout)

def error(message) 
  $LOG.fatal(message)
  exit 
end

if ARGV.include? '--example'
  example = File.dirname(__FILE__) + '/example.yml'
  error open(example).read 
end

error "Usage: slicehost-dns (--dump --dry) [config.yml]" if ARGV.empty?

dump = ARGV.delete('--dump')
dry_run = ARGV.delete('--dry')
filename = ARGV.shift
config = YAML.load_file(filename)
API = config.delete('api')
$TTL = 43200 # 12 hours. 

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
      $LOG.info("~> dry saving zone #{origin}")
    end
    def destroy
      $LOG.info("~> dry destroying zone #{origin}")
    end
  end
  class Record
    def save
      $LOG.info("~> dry saving record #{kind} #{name}: #{data}")
    end
    def destroy
      $LOG.info("~> dry destroying record #{kind} #{name}: #{data}")
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
  
  File.open(filename, 'w') {|f| YAML.dump(output, f) }
else
  config.each_pair do |ip, domains|
    unless ip.match(/(\d+\.){3}\d+/)
      $LOG.warn "\n~ skipping key #{ip}, not a valid ip address"
      next
    end
    domains.each_pair do |domain, desired_records|
      $LOG.info "\ndomain #{domain}"
      zone = zones.detect {|z| z.domain == domain } || Zone.create_for_domain(domain)
      records_for_domain, records = records.partition {|r| r.zone_id == zone.id }
      Reconciler.new(zone, ip, records_for_domain, desired_records).process!
      zones.delete(zone)
    end
    puts "\n\ni'd delete #{zones.map{|z| z.domain}.join(', ')} now but you'd hate me."
  end
end