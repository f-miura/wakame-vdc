require 'rubygems'
require 'test/unit'
require 'active_resource'

require File.expand_path('../../../../lib/models/dcmgr_resource/base')
require File.expand_path('../../../../lib/models/dcmgr_resource/instance')

module Frontend
  class TestVolume < Test::Unit::TestCase
    def setup
      @instance = Frontend::Models::DcmgrResource::Instance
    end

    def teardown
    end

    def test_list
      params = {
        :start => 0,
        :limit => 10
      }
      require 'pp'
      pp @instance.list(params)
    end
    
    def test_show
      instance_id = 'i-sahh531g'
      p @instance.show(instance_id)
    end
    
  end
end