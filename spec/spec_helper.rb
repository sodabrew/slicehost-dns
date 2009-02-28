require 'rubygems'
require 'activeresource'

begin
  require 'spec'
rescue LoadError
  gem 'rspec'
  require 'spec'
end

gem 'ruby-debug'
require 'ruby-debug'

Debugger.start

class Zone < ActiveResource::Base
  self.site = '/'
  def save
    self.id ||= '12345'
  end
end
class Record < ActiveResource::Base
  self.site = '/'
  def save
    self.id ||= '12345'
  end
  def destroy; end
end