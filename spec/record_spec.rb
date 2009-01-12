require File.dirname(__FILE__) + '/spec_helper.rb'
require File.expand_path(File.dirname(__FILE__) + '/../lib/record')

describe Record do
  
  it "updates the ttl" do
    @record = Record.new(:ttl => nil)
    @record.update_ttl!
    @record.ttl.should == $TTL
  end
  
end