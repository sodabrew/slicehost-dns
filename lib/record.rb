class Record < ActiveResource::Base

  def kind
    record_type.downcase
  end

  [:a,:mx,:cname,:srv,:ns,:txt].each do |kind|
    define_method "#{kind}?" do
      self.kind == "#{kind}"
    end
  end

end