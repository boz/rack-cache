# coding: utf-8
require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/entitystore'

class Object
  def sha_like?
    length == 40 && self =~ /^[0-9a-z]+$/
  end
end

describe_shared 'A Rack::Cache::EntityStore Implementation' do

  it 'responds to all required messages' do
    %w[read open write exist? ].each do |message|
      @store.should.respond_to message
    end
  end

  it 'stores bodies with #write' do
    key, size = @store.write(['My wild love went riding,'])
    key.should.not.be.nil
    key.should.be.sha_like

    data = @store.read(key)
    data.should.equal 'My wild love went riding,'
  end

  it 'correctly determines whether cached body exists for key with #exist?' do
    key, size = @store.write(['She rode to the devil,'])
    @store.should.exist key
    @store.should.not.exist '938jasddj83jasdh4438021ksdfjsdfjsdsf'
  end

  it 'can read data written with #write' do
    key, size = @store.write(['And asked him to pay.'])
    data = @store.read(key)
    data.should.equal 'And asked him to pay.'
  end

  it 'gives a 40 character SHA1 hex digest from #write' do
    key, size = @store.write(['she rode to the sea;'])
    key.should.not.be.nil
    key.length.should.equal 40
    key.should.be =~ /^[0-9a-z]+$/
    key.should.equal '90a4c84d51a277f3dafc34693ca264531b9f51b6'
  end

  it 'returns the entire body as a String from #read' do
    key, size = @store.write(['She gathered together'])
    @store.read(key).should.equal 'She gathered together'
  end

  it 'returns nil from #read when key does not exist' do
    @store.read('87fe0a1ae82a518592f6b12b0183e950b4541c62').should.be.nil
  end

  it 'returns a Rack compatible body from #open' do
    key, size = @store.write(['Some shells for her hair.'])
    body = @store.open(key)
    body.should.respond_to :each
    buf = ''
    body.each { |part| buf << part }
    buf.should.equal 'Some shells for her hair.'
  end

  it 'returns nil from #open when key does not exist' do
    @store.open('87fe0a1ae82a518592f6b12b0183e950b4541c62').should.be.nil
  end

  it 'can store largish bodies with binary data' do
    pony = File.open(File.dirname(__FILE__) + '/pony.jpg', 'rb') { |f| f.read }
    key, size = @store.write([pony])
    key.should.equal 'd0f30d8659b4d268c5c64385d9790024c2d78deb'
    data = @store.read(key)
    data.length.should.equal pony.length
    data.hash.should.equal pony.hash
  end

  it 'deletes stored entries with #purge' do
    key, size = @store.write(['My wild love went riding,'])
    @store.purge(key).should.be.nil
    @store.read(key).should.be.nil
  end

  it "writes an application response" do
    body = "hello world"
    response = mock_response(200, {}, [body])
    @store.write_response(response)
    response.headers['Content-Length'].should == body.size.to_s
    digest = response.headers['X-Content-Digest']
    digest.should.not.nil
    @store.should.exist(digest)
  end

  it "restores a saved application response" do
    body     = "hello world"
    response = mock_response(200, {}, [body])
    @store.write_response(response)
    restored = @store.restore_response(response.headers)
    restored.should.not.nil
    restored.should.not == response
    restored.headers['Content-Length'].should == body.size.to_s
  end

  # Helper Methods =============================================================
  define_method :mock_response do |status,headers,body|
    headers ||= {}
    body = Array(body).compact
    Rack::Cache::Response.new(status, headers, body)
  end
end

describe_shared 'A Rack::Cache::EntityStore::Disk Implementation' do
  it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
  before do
    @temp_dir = create_temp_directory
    @store = Rack::Cache::EntityStore::Disk.new(@temp_dir)
  end
  after do
    @store = nil
    remove_entry_secure @temp_dir
  end
  it 'takes a path to ::new and creates the directory' do
    path = @temp_dir + '/foo'
    @store = Rack::Cache::EntityStore::Disk.new(path)
    File.should.be.a.directory path
  end
  it 'produces a body that responds to #to_path' do
    key, size = @store.write(['Some shells for her hair.'])
    body = @store.open(key)
    body.should.respond_to :to_path
    path = "#{@temp_dir}/#{key[0..1]}/#{key[2..-1]}"
    body.to_path.should.equal path
  end
  it 'spreads data over a 36² hash radius' do
    (<<-PROSE).each_line { |line| @store.write([line]).first.should.be.sha_like }
      My wild love went riding,
      She rode all the day;
      She rode to the devil,
      And asked him to pay.

      The devil was wiser
      It's time to repent;
      He asked her to give back
      The money she spent

      My wild love went riding,
      She rode to sea;
      She gathered together
      Some shells for her hair

      She rode on to Christmas,
      She rode to the farm;
      She rode to Japan
      And re-entered a town

      My wild love is crazy
      She screams like a bird;
      She moans like a cat
      When she wants to be heard

      She rode and she rode on
      She rode for a while,
      Then stopped for an evening
      And laid her head down

      By this time the weather
      Had changed one degree,
      She asked for the people
      To let her go free

      My wild love went riding,
      She rode for an hour;
      She rode and she rested,
      And then she rode on
      My wild love went riding,
    PROSE
    subdirs = Dir["#{@temp_dir}/*"]
    subdirs.each do |subdir|
      File.basename(subdir).should.be =~ /^[0-9a-z]{2}$/
      files = Dir["#{subdir}/*"]
      files.each do |filename|
        File.basename(filename).should.be =~ /^[0-9a-z]{38}$/
      end
      files.length.should.be > 0
    end
    subdirs.length.should.equal 28
  end
end

describe 'Rack::Cache::EntityStore' do

  describe 'Heap' do
    it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
    before { @store = Rack::Cache::EntityStore::Heap.new }
    it 'takes a Hash to ::new' do
      @store = Rack::Cache::EntityStore::Heap.new('foo' => ['bar'])
      @store.read('foo').should.equal 'bar'
    end
    it 'uses its own Hash with no args to ::new' do
      @store.read('foo').should.be.nil
    end
  end

  describe_shared 'DISK' do
    it_should_behave_like 'A Rack::Cache::EntityStore::Disk Implementation'

    it "write an application response and return the body" do
      body = "hello world"
      response = mock_response(200, {}, [body])
      @store.write_response(response)
      response.body.should == [body]
    end

    describe "it should restore the response body" do
      body     = "hello world"
      response = mock_response(200, {}, [body])
      @store.write_response(response)
      restored = @store.restore_response(response.headers)
      restored.body.should == response.body
    end
  end

  describe 'AccelRedirect' do
    it_should_behave_like 'A Rack::Cache::EntityStore::Disk Implementation'
    before do
      @temp_dir = create_temp_directory
      @redirect = "/cache"
      @store = Rack::Cache::EntityStore::AccelRedirect.new(@temp_dir,@redirect)
    end

    after do
      @store = nil
    end

    it "should parse redirect_root from the uri fragment" do
      store = Rack::Cache::EntityStore::AccelRedirect::resolve(URI.parse("accelredirect:/foo/bar"))
      store.root.should          == "/foo/bar"
      store.redirect_root.should == "/cache"

      store = Rack::Cache::EntityStore::AccelRedirect::resolve(URI.parse("accelredirect:/foo/bar#baz"))
      store.root.should          == "/foo/bar"
      store.redirect_root.should == "/baz"
    end

    it "sets x-accel-redirect when writing an application response" do
      body = "hello world"
      response = mock_response(200, {}, [body])
      @store.write_response(response)
      response.body.should == ""
      response.headers['X-Accel-Redirect'].should == @store.__send__(:cache_path,response.headers['X-Content-Digest'])
    end

    it "sets x-accel-redirect when restoring an application response" do
      body     = "hello world"
      response = mock_response(200, {}, [body])
      @store.write_response(response)
      restored = @store.restore_response(response.headers)
      restored.body.should == ""
      restored.headers['X-Accel-Redirect'].should == @store.__send__(:cache_path,response.headers['X-Content-Digest'])
    end
  end

  need_memcached 'entity store tests' do
    describe 'MemCached' do
      it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
      before do
        @store = Rack::Cache::EntityStore::MemCached.new($memcached)
      end
      after do
        @store = nil
      end
    end
  end


  need_memcache 'entity store tests' do
    describe 'MemCache' do
      it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
      before do
        $memcache.flush_all
        @store = Rack::Cache::EntityStore::MemCache.new($memcache)
      end
      after do
        @store = nil
      end
    end
  end
  
  need_java 'entity store testing' do
    module Rack::Cache::AppEngine
      module MC
        class << (Service = {})
 
          def contains(key); include?(key); end
          def get(key); self[key]; end;
          def put(key, value, ttl = nil)
            self[key] = value
          end  
        end
        
      end
    end
    
    describe 'GAEStore' do
      it_should_behave_like 'A Rack::Cache::EntityStore Implementation'
      before do
        puts Rack::Cache::AppEngine::MC::Service.inspect
        @store = Rack::Cache::EntityStore::GAEStore.new
      end
      after do
        @store = nil
      end
    end
  end
end
