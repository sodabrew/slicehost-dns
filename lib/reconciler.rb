class Reconciler
  def initialize(zone, ip, existing, desired, setup={})
    @zone, @ip, @existing, @desired, @setup = zone, ip, existing, desired, setup
  end
  
  def log(msg, level=:info)
    $LOG.send(level, msg) if $LOG
  end
  
  def process!
    process_a_records
    process_cname_records
    process_mx_records
    process_srv_records
    process_txt_records
    process_ns_records
  end
  
  def process_a_records
    a_records = @existing.select {|r| r.a? }
    
    desired = @desired['a'] ||= {}
    desired[@zone.origin] = 'this'
    desired['*'] ||= 'this'
    desired.each_pair {|k,v| desired[k] = @ip if v == "this" }
    
    crud_by_name(:a, a_records, desired)
  end
  
  def process_cname_records
    cnames = @existing.select {|r| r.cname? }
    desired = @desired['cname'] || {}
    crud_by_name(:cname, cnames, desired)
  end
  
  def process_ns_records
    ns = @existing.select {|r| r.ns? }
    (1..3).to_a.each do |i|
      unless ns.any? {|r| r.data == "ns#{i}.slicehost.net." }
        log "> creating NS record ns#{i}.slicehost.net."
        record = @zone.new_record(:record_type => "NS", :name => @zone.origin, :data => "ns#{i}.slicehost.net.")
        record.save
      else
        r = ns.detect {|r| r.data == "ns#{i}.slicehost.net." }
        ns.delete(r)
      end
    end
    destroy_records ns
  end
  
  def process_mx_records
    mx = @existing.select {|r| r.mx? }
    desired = @desired['mx'] || {}

    # Process GOOG records
    
    if desired.kind_of?(String)
      desired = {desired => 5}
    end
      
    keepers = mx.select {|r| desired.has_key?(r.data) }
    
    cru_by_data :mx, @zone.origin, keepers, desired
    
    mx -= keepers
    destroy_records mx
  end
  
  def process_srv_records
    srv = @existing.select {|r| r.srv? }
    desired = @desired['srv'] || {}

    # Process GOOG records
    
    desired.each_pair do |name, data_aux_pairs|
      keepers = srv.select {|r| r.name == name }.select {|r| data_aux_pairs.has_key?(r.data) }
      srv -= keepers
      cru_by_data(:srv, name, keepers, data_aux_pairs)
    end
    
    destroy_records srv
  end
  
  def process_txt_records
    txt = @existing.select {|r| r.txt? }
    desired = @desired['txt'] || []

    # Process GOOG records

    desired = desired.inject({}) {|memo, value| memo.update({value => 0}) }
    
    keepers = txt.select {|r| desired.include?(r.data) }
    txt -= keepers
    cru_by_data(:txt, @zone.origin, keepers, desired)
    
    destroy_records txt
  end
  
  def destroy_records(records=[])
    records.each do |r|
      log "> removing record: #{r.kind} #{r.name} #{r.data}"
      r.destroy
    end
  end
  
  # A, CNAME
  def crud_by_name(type, records, desired)
    type = type.to_s.upcase
    records.each do |record|
      if desired[record.name] == record.data
        desired.delete(record.name)
        
      elsif desired.has_key?(record.name)
        log "> changing record: #{type} #{record.name} from #{record.data} to #{desired[record.name]}"
        record.data = desired[record.name]
        desired.delete(record.name)
        record.save
        
      else
        log "> removing record: #{type} #{record.name} (#{record.data})"
        record.destroy
      end
    end
    (desired || {}).each_pair do |name, data|
      log "> creating record: #{type} #{name} (#{data})"
      record = @zone.new_record(:record_type => type, :name => name, :data => data)
      record.save
    end
    
  end
  
  # MX, SRV, TXT
  def cru_by_data(type, name, keepers, desired)
    type = type.to_s.upcase
    
    keepers.each do |r|
      unless r.aux == desired[r.data]
        log "> changing record: #{type} #{r.name} #{r.data} from #{r.aux} to #{desired[r.data]}"
        r.aux = desired[r.data]
        r.save
      end
      desired.delete(r.data)
    end
    
    desired.each_pair do |data, aux|
      log "> creating record: #{type} #{name} (#{data} / #{aux})"
      r = @zone.new_record(:record_type => type, :name => name, :data => data, :aux => aux)
      r.save
    end
    
  end
  
end