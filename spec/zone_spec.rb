require File.dirname(__FILE__) + '/spec_helper.rb'
require File.expand_path(File.dirname(__FILE__) + '/../lib/zone')

describe Zone do
  
  describe "creating for a domain" do
    before do
      @zone = Zone.create_for_domain('example.com')
    end
    
    it "sets the origin" do
      @zone.origin.should == 'example.com.'
    end
    
    it "saves the record" do
      @zone.id.should == '12345'
    end
  end
  
  describe "creating a new record" do
    before do
      @zone = Zone.new
      @zone.save
      @record = @zone.new_record
    end
    
    it "has the zone's id" do
      @record.zone_id.should == @zone.id
    end
  end
  
end