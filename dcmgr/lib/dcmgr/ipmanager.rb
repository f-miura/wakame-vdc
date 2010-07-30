# -*- coding: utf-8 -*-

module Dcmgr
  module IPManager
    extend self

    class NoAssignIPError < StandardError; end

    @check_assigned = @default_check_assigned = lambda{|ip|
      ip.instance.nil?
    }
    
    def set_assigned?(&block)
      @check_assigned = block
    end

    def set_default_assigned?
      @check_assigned = @default_check_assigned
    end
    

    # pick each IP from respective groups. The newbr0 group only be
    # looked up for the time being.
    def assign_ips(instance)
      Dcmgr.db.transaction do
        %w(newbr0).each { |i|
          ds = Models::Ip.find_by_group_name(i).filter('instance_id IS NULL')
          raise "no available IP in #{i} group" if ds.count < 1
          assigned_ip = ds.limit(1, rand(ds.count)).first
          assigned_ip.instance = instance
          assigned_ip.save
          Dcmgr::logger.debug "assigned ip: [#{instance.uuid}], mac: #{assigned_ip[:mac]}, ip: #{assigned_ip[:ip]}"
        }
      end      
    end
    
    private

    def assign_ips_to(instance, ips)
      ips.each{|ip|
        ip_obj = ip[:ip]
        ip_obj.instance = instance
        ip_obj.save
      }
    end
  end
end