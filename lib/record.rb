class Record < ActiveResource::Base

  def self.find_by_domain(domain)
    Record.find(:all, :params => { :origin => domain })
  end
  
  def kind
    record_type.downcase
  end

  [:a,:mx,:cname,:srv,:ns,:txt].each do |kind|
    define_method "#{kind}?" do
      self.kind == "#{kind}"
    end
  end

end
