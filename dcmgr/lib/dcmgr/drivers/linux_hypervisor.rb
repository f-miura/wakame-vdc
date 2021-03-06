# -*- coding: utf-8 -*-

require 'fileutils'

module Dcmgr
  module Drivers
    # Abstract class for Linux based hypervisors.
    class LinuxHypervisor < Hypervisor
      include Dcmgr::Helpers::NicHelper
      include Dcmgr::Helpers::CliHelper
      include Dcmgr::Helpers::TemplateHelper

      template_base_dir 'linux'
      
      def check_interface(hc)
        hc.inst[:instance_nics].each { |vnic|
          next if vnic[:network].nil?

          network = hc.rpc.request('hva-collector', 'get_network', vnic[:network_id])
          
          network_name = network[:dc_network][:name]
          dcn = Dcmgr.conf.dc_networks[network_name]
          if dcn.nil?
            raise "Missing local configuration for the network: #{network_name}"
          end
          unless valid_nic?(dcn.interface)
            raise "Interface not found for the network #{network_name}: #{dcn.interface}"
          end
          unless valid_nic?(dcn.bridge)
            raise "Bridge not found for the network #{network_name}: #{dcn.bridge}"
          end
          
          fwd_if = dcn.interface
          bridge_if = dcn.bridge

          if network[:dc_network][:vlan_lease]
            fwd_if = "#{dcn.interface}.#{network[:dc_network][:vlan_lease][:tag_id]}"
            bridge_if = network[:dc_network][:uuid]
            unless valid_nic?(fwd_if)
              sh("/sbin/vconfig add #{phy_if} #{network[:vlan_id]}")
              sh("/sbin/ip link set %s up", [fwd_if])
              sh("/sbin/ip link set %s promisc on", [fwd_if])
            end

            # create new bridge only when the vlan is assigned to customer.
            unless valid_nic?(bridge_if)
              sh("#{Dcmgr.conf.brctl_path} addbr %s",    [bridge_if])
              sh("#{Dcmgr.conf.brctl_path} setfd %s 0",    [bridge_if])
              # There is null case for the forward interface to create closed bridge network.
              if fwd_if
                sh("#{Dcmgr.conf.brctl_path} addif %s %s", [bridge_if, fwd_if])
              end
            end
          end
        }
        sleep 1
      end

      def setup_metadata_drive(hc,metadata_items)
        begin
          inst_data_dir = hc.inst_data_dir
          FileUtils.mkdir(inst_data_dir) unless File.exists?(inst_data_dir)
          
          logger.info("Setting up metadata drive image for :#{hc.inst_id}")
          # truncate creates sparsed file.
          sh("/usr/bin/truncate -s 10m '#{hc.metadata_img_path}'; sync;")
          sh("parted %s < %s", [hc.metadata_img_path, LinuxHypervisor.template_real_path('metadata.parted')])
          res = sh("kpartx -av %s", [hc.metadata_img_path])
          if res[:stdout] =~ /^add map (\w+) /
            lodev="/dev/mapper/#{$1}"
          else
            raise "Unexpected result from kpartx: #{res[:stdout]}"
          end
          sh("udevadm settle")
          sh("mkfs.vfat -n METADATA %s", [lodev])
          Dir.mkdir("#{hc.inst_data_dir}/tmp") unless File.exists?("#{hc.inst_data_dir}/tmp")
          sh("/bin/mount -t vfat #{lodev} '#{hc.inst_data_dir}/tmp'")
          
          # build metadata directory tree
          metadata_base_dir = File.expand_path("meta-data", "#{hc.inst_data_dir}/tmp")
          FileUtils.mkdir_p(metadata_base_dir)
          
          metadata_items.each { |k, v|
            if k[-1,1] == '/' && v.nil?
              # just create empty folder
              FileUtils.mkdir_p(File.expand_path(k, metadata_base_dir))
              next
            end
            
            dir = File.dirname(k)
            if dir != '.'
              FileUtils.mkdir_p(File.expand_path(dir, metadata_base_dir))
            end
            File.open(File.expand_path(k, metadata_base_dir), 'w') { |f|
              f.puts(v.to_s)
            }
          }
          # user-data
          File.open(File.expand_path('user-data', "#{hc.inst_data_dir}/tmp"), 'w') { |f|
            f.puts(hc.inst[:user_data])
          }
        ensure
          # ignore any errors from cleanup work.
          sh("/bin/umount -l %s", ["#{hc.inst_data_dir}/tmp"]) rescue logger.warn($!.message)
          sh("kpartx -d %s", [hc.metadata_img_path]) rescue logger.warn($!.message)
          sh("udevadm settle")
        end
      end
    end
  end
end
