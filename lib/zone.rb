class Zone < ActiveResource::Base
  
  def domain
    origin.sub(/\.$/,'')
  end
  
  def self.create_for_domain(domain)
    $LOG.info "> domain record doesn't exist yet, creating" if $LOG
    zone = self.new(:origin => "#{domain}.")
    zone.save
    zone
  end
  
  def self.find_by_domain(domain)
    Zone.find(:all, :params => { :origin => domain })
  end
  
  def new_record(attrs={})
    Record.new(attrs.merge({:zone_id => id}))
  end

end
