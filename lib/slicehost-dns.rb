#! /usr/bin/env ruby

require 'rubygems'
require 'activeresource'
require 'yaml'
require 'logger'

$:.unshift File.dirname(__FILE__)
require 'zone'
require 'record'
require 'reconciler'

class SlicehostDNS
  attr_accessor :zones, :records, :apikey

  def initialize(apikey, domain)
    @apikey = apikey
    Zone.site = "https://#{@apikey}@api.slicehost.com/"
    Record.site = "https://#{@apikey}@api.slicehost.com/"

    if domain
      @zones = Zone.find_by_domain domain
      @records = Record.find_by_domain domain
    else
      @zones = Zone.find :all
      @records = Record.find :all
    end

  end

  def dump(filename)
    output = {}
    output['api'] = @apikey
    
    @zones.each do |zone|
      local, @records = @records.partition {|r| r.zone_id == zone.id }
      
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
  end

  # Delete the specified domain and all of its records
  def delete(domain)
    zone = @zones.detect {|z| z.domain == domain }
    return unless zone

    records_for_domain, records = @records.partition {|r| r.zone_id == zone.id }
    Reconciler.destroy_records records_for_domain
  end

  # Compare the slicehost records for this user with the records in the config
  # and make changes on the slicehost side to match the config
  def process_config(config, delete_extra)
    # Pull out the templates section
    templates = {}
    templates = config.delete('templates')

    # Loop over the IPs and their domains
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
        zone = @zones.detect {|z| z.domain == domain } || Zone.create_for_domain(domain)
        records_for_domain, @records = @records.partition {|r| r.zone_id == zone.id }
 
        $LOG.debug "\ndomain #{domain}:" unless using_template
        $LOG.debug "\ndomain #{domain} using template for #{ip}:" if using_template
 
        # Tell us what needs to be done
        # Reconciler.new(zone, ip, records_for_domain, desired_records).report!
        #puts YAML.dump(records_for_domain)
 
        # Do what needs to be done
        Reconciler.new(zone, ip, records_for_domain, desired_records).process!
 
        @zones.delete(zone)
      end
    end

    leftovers = @zones.map{|z| z.domain}.join(', ') unless @zones.empty?
    if delete_extra and leftovers
      puts "TODO: Delete #{leftovers}."
    end
  end
end
