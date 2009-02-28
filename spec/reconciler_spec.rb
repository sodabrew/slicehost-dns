require File.dirname(__FILE__) + '/spec_helper.rb'
require File.expand_path(File.dirname(__FILE__) + '/../lib/reconciler')
require File.expand_path(File.dirname(__FILE__) + '/../lib/zone')
require File.expand_path(File.dirname(__FILE__) + '/../lib/record')

describe Reconciler do
  before do
    @ip = '1.1.1.1'
    @domain = 'example.com.'
    @zone = Zone.new(:origin => @domain, :id => '1')
  end
  
  def reconciler
    @reconciler = Reconciler.new(@zone, @ip, @existing, @desired)
  end
  
  def record(type, name, data, aux=0)
    @zone.new_record(:record_type => type, :name => name, :data => data :aux => aux)
  end
  
  describe "A records" do
    def records recs
      @existing = recs.map {|r| record('A', r[:name], r[:data]) }
    end
    
    describe "primary" do
      def seed_records(value)
        records [{:name => @domain, :data => value}, {:name => '*', :data => value}]
      end
      
      describe "for a new zone" do
        before do
          records [{:name => '*', :data => @ip}]
          @desired = {}
        end
        
        it "creates the A record" do
          args = {:record_type => 'A', :name => @domain, :data => @ip}
          @record = @zone.new_record(args)
          @zone.should_receive(:new_record).with(args).and_return(@record)
          @record.should_receive(:save)
          reconciler
          @reconciler.process_a_records
        end
      end
      
      describe "with a different ip" do
        before do
          seed_records '10.1.1.1'
          @desired = {}
        end
        
        it "updates the A record" do
          @existing.first.should_receive(:data=).with(@ip)
          @existing.first.should_receive(:save)
          reconciler
          @reconciler.process_a_records
        end
      end
      
      describe "with the same ip" do
        before do
          seed_records @ip
          @desired = {}
        end
        
        it "does nothing" do
          @existing.first.should_not_receive(:save)
          reconciler
          @reconciler.process_a_records
        end
      end
    end
    
    describe "secondary" do
      def seed_records(name, value)
        records [{:name => @domain, :data => @ip}, {:name => name, :data => value}]
      end
      
      it "creates a wildcard record if it doesn't exist" do
        records [{:name => @domain, :data => @ip}]
        @desired = {}
        r = mock('record')
        @zone.should_receive(:new_record).with(:name => '*', :data => @ip, :record_type => 'A').and_return(r)
        r.should_receive(:save)
        reconciler
        @reconciler.process_a_records
      end
      
      describe "with a 'this' value" do
        before do
          records [{:name => @domain, :data => @ip}, {:name => '*', :data => @ip}]
          @desired = {'a' => {'mail' => 'this'}}
          reconciler
        end
        
        it "sets the 'this' values to the current ip" do
          @record = @zone.new_record
          @zone.should_receive(:new_record).with({:name => 'mail', :data => @ip, :record_type => 'A'}).and_return(@record)
          @reconciler.process_a_records
        end
      end
    end
    
  end
    
  describe "crud_by_name" do
    before do
      @existing = [
        {:name => 'same', :data => 'foo'}, 
        {:name => 'changed', :data => 'foo'},
        {:name => 'old', :data => 'baz'}
      ].map {|r| record("CNAME", r[:name], r[:data])}
      
      @desired = { 'same' => 'foo', 'changed' => 'bar', 'new' => 'baz' }
    end
    
    def run
      reconciler
      @reconciler.crud_by_name(:cname, @existing, @desired)
    end
    
    it "creates a desired record that doesn't exist" do
      @record = @zone.new_record
      @zone.should_receive(:new_record).with({:record_type => 'CNAME', :name => 'new', :data => 'baz'}).and_return(@record)
      @record.should_receive(:save)
      run
    end
    
    it "updates an existing record that differs from the desired record" do
      @differ = @existing.detect {|r| r.name == 'changed' }
      @differ.should_receive(:data=).with('bar').ordered
      @differ.should_receive(:save).ordered
      run
    end
    
    it "does not update a desired record that is the same as the existing record" do
      @same = @existing.detect {|r| r.name == 'same' }
      @same.should_not_receive(:save)
      run
    end
    
    it "deletes an existing record that does not have a corresponding desired record" do
      @old = @existing.detect {|r| r.name == 'old' }
      @old.should_receive(:destroy)
      run
    end
  end
  
  describe "ns records" do
    it "creates them when they don't exist" do
      @existing = []
      @desired = {}
      reconciler
      (1..3).to_a.each do |i|
        record = mock("record#{i}")
        @zone.should_receive(:new_record).with({:record_type => 'NS', :name => @domain, :data => "ns#{i}.slicehost.net."}).and_return(record)
        record.should_receive(:save)
      end
      
      @reconciler.process_ns_records
    end
    
    it "leaves them alone when they do exist" do
      @existing = (1..3).to_a.map {|i| @zone.new_record(:record_type => 'NS', :name => @domain, :data => "ns#{i}.slicehost.net.") }
      @desired = {}
      reconciler
      @existing.each {|r| r.should_not_receive(:save) }
      @reconciler.process_ns_records
    end
  end
  
  describe "mx records" do
    def run
      reconciler
      @reconciler.process_mx_records
    end
    
    describe "with a single record" do
      it "leaves correct existing records alone" do
        @existing = [record('MX', @domain, 'mail.example.com.', 5)]
        @desired = {'mx' => 'mail.example.com.'}
        @existing.first.should_not_receive(:save)
        @existing.first.should_not_receive(:destroy)
        run
      end
      
      it "updates incorrect existing records" do
        @existing = [record('MX', @domain, 'old.example.com.')]
        @desired = {'mx' => 'mail.example.com.'}
        @existing.first.should_receive(:destroy)
        @record = @zone.new_record
        @zone.should_receive(:new_record).with(:record_type => 'MX', :name => @domain, :data => 'mail.example.com.', :aux => 5).and_return(@record)
        @record.should_receive(:save)
        run
      end
      
      it "creates nonexistant desired records" do
        @existing = []
        @desired = {"mx" => 'mail.example.com.'}
        @record = @zone.new_record
        @zone.should_receive(:new_record).with(:record_type => 'MX', :name => @domain, :data => 'mail.example.com.', :aux => 5).and_return(@record)
        @record.should_receive(:save)
        
        run
      end
      
      it "removes existing records not desired" do
        @existing = [record('MX', @domain, 'mail.exmaple.com.')]
        @desired = {}
        @existing.first.should_receive(:destroy)
        run
      end
    end
    
    describe "with multiple records" do
      before do
        @existing = [
          record('MX', @domain, 'mail.example.com.', 5),
          record('MX', @domain, 'old.example.com.', 10),
          record('MX', @domain, 'lastresort.com.', 20)
        ]
        @desired = {'mx' => {'mail.example.com.' => 5, 'backupmail.com.' => 20, 'lastresort.com.' => 30}}
      end
      
      it "leaves correct existing records alone" do
        @existing.first.should_not_receive(:save)
        @existing.first.should_not_receive(:destroy)
        run
      end
      
      it "removes existing records not desired" do
        @existing.detect {|r| r.data == 'old.example.com.'}.should_receive(:destroy)
        run
      end
      
      it "creates nonexisting desired records" do
        @record = @zone.new_record
        @zone.should_receive(:new_record).with({:record_type => 'MX', :name => @domain, :data => 'backupmail.com.', :aux => 20}).and_return(@record)
        @record.should_receive(:save)
        run
      end
      
      it "updates existing records with bad aux value" do
        record = @existing.detect {|r| r.data == 'lastresort.com.' }
        record.should_receive(:aux=).with(30)
        record.should_receive(:save)
        run
      end
    end
    
    describe "with google apps" do
      before do
        @desired = {"goog" => "mail", "mx" => {"mail.example.com" => 5}}
        @gmail = {
          'aspmx.l.google.com.' => 1, 
          'alt1.aspmx.l.google.com.' => 5, 
          'alt2.aspmx.l.google.com.' => 5, 
          'aspmx2.googlemail.com.' => 10,
          'aspmx3.googlemail.com.' => 10,
          'aspmx4.googlemail.com.' => 10,
          'aspmx5.googlemail.com.' => 10
        }
      end
      
      it "ignores any given mx records" do
        @existing = [record('MX', @domain, 'mail.example.com.', 5)]
        @existing.first.should_receive(:destroy)
        run
      end
      
      it "creates google mx records if they don't exist" do
        @existing = []
        @gmail.each_pair do |data, aux|
          r = mock("gmail#{data}")
          @zone.should_receive(:new_record).with({:record_type => 'MX', :name => @domain, :data => data, :aux => aux}).and_return(r)
          r.should_receive :save
        end
        run
      end
      
      it "leaves correct existing google mx records alone" do
        @existing = []
        @gmail.each_pair {|data, aux| @existing << record('MX', @domain, data, aux) }
        @existing.each {|r| r.should_not_receive(:save) }
        run
      end
    end
  end
  
  describe "srv records" do
    before do
      @existing = [
        record('SRV', '_sip._tcp.example.com.', '60 5060 sip.example.com.', 5),
        record('SRV', '_sip._tcp.example.com.', '60 5060 old.example.com.', 10),
        record('SRV', '_sip._tcp.example.com.', '10 5060 etc.example.com.', 20)
      ]
      @desired = {'srv' => {'_sip._tcp.example.com.' => {
        '60 5060 sip.example.com.' => 5,
        '20 5060 new.example.com.' => 20,
        '10 5060 etc.example.com.' => 30,
      }}}
    end
    
    def run
      reconciler
      @reconciler.process_srv_records
    end
    
    it "leaves correct existing records alone" do
      @existing.first.should_not_receive(:save)
      @existing.first.should_not_receive(:delete)
      run
    end
    
    it "removes existing records not desired" do
      @existing[1].should_receive(:destroy)
      run
    end
    
    it "creates nonexisting desired records" do
      @record = @zone.new_record
      @zone.should_receive(:new_record).with({:record_type => 'SRV', :name => '_sip._tcp.example.com.', :data => '20 5060 new.example.com.', :aux => 20}).and_return(@record)
      @record.should_receive(:save)
      run
    end
    
    it "updates existing records with bad aux value" do
      record = @existing.last
      record.should_receive(:aux=).with(30)
      record.should_receive(:save)
      run
    end
    
    describe "google apps" do
      before do
        @desired['goog'] = true
        @desired.delete('srv')
        @gchat = {
          '_xmpp-server._tcp.example.com.' => {
            '0 5269 xmpp-server.l.google.com.' => 5,
            '0 5269 xmpp-server1.l.google.com.' => 20,
            '0 5269 xmpp-server2.l.google.com.' => 20,
            '0 5269 xmpp-server3.l.google.com.' => 20,
            '0 5269 xmpp-server4.l.google.com.' => 20
          },
          '_jabber._tcp.example.com.' => {
            '0 5269 xmpp-server.l.google.com.' => 5,
            '0 5269 xmpp-server1.l.google.com.' => 20,
            '0 5269 xmpp-server2.l.google.com.' => 20,
            '0 5269 xmpp-server3.l.google.com.' => 20,
            '0 5269 xmpp-server4.l.google.com.' => 20
          },
          '_xmpp-client._tcp.example.com.' => {
            '0 5222 talk.l.google.com.' => 5,
            '0 5222 talk1.l.google.com.' => 20,
            '0 5222 talk2.l.google.com.' => 20
          }
        }
      end
      
      it "creates records for google chat" do
        @gchat.each_pair do |name, data_aux_pairs|
          data_aux_pairs.each do |data, aux|
            r = mock("srv-#{name}-#{data}")
            @zone.should_receive(:new_record).with(:record_type => "SRV", :name => name, :data => data, :aux => aux).and_return(r)
            r.should_receive(:save)
          end
        end
        run
      end
      
      it "deletes existing records" do
        @existing.each {|r| r.should_receive(:destroy) }
        run
      end
    end
  end
  
  describe "txt records" do
    def run
      reconciler
      @reconciler.process_txt_records
    end
    
    before do
      @existing = [
        record('TXT', @zone.origin, 'correct-existing'),
        record('TXT', @zone.origin, 'to-be-removed')
      ]
      @desired = {'txt' => %w(correct-existing to-be-created)}
    end
    
    it "leaves existing records alone" do
      @existing.first.should_not_receive(:save)
      @existing.first.should_not_receive(:destroy)
      run
    end
    
    it "creates nonexisting records" do
      @record = @zone.new_record
      @zone.should_receive(:new_record).with({:record_type => 'TXT', :name => @zone.origin, :data => 'to-be-created', :aux => 0}).and_return(@record)
      @record.should_receive(:save)
      run
    end
    
    it "removes non-desired records" do
      @existing.last.should_receive(:destroy)
      run
    end
    
    describe "google apps" do
      before do
        @desired['goog'] = true
        @desired['txt'] = []
      end
      
      it "creates spf record if nonexistant" do
        r = mock('spf')
        @zone.should_receive(:new_record).with({:record_type => "TXT", :name => @zone.origin, :data => "v=spf1 include:aspmx.googlemail.com ~all", :aux => 0}).and_return(r)
        r.should_receive(:save)
        run
      end
      
      it "leaves existing spf record alone EVEN IF it differs from standard" do
        @existing = [record('TXT', @zone.origin, 'v=spf1 a include:aspmx.googlemail.com ~all')]
        @desired['txt'] = ['v=spf1 a include:aspmx.googlemail.com ~all']
        @existing.first.should_not_receive(:destroy)
        @zone.should_not_receive(:new_record)
        run
      end
    end
  end
  
end