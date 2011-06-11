module Dcmgr
  module Drivers
    class Kvm < Hypervisor
      include Dcmgr::Logger
      include Dcmgr::Helpers::CliHelper
      include Dcmgr::Rpc::KvmHelper
      include Dcmgr::Helpers::NicHelper

      def run_instance(hc)
        # run vm
        inst = hc.inst
        cmd = "kvm -m %d -smp %d -name vdc-%s -vnc :%d -drive file=%s -pidfile %s -daemonize -monitor telnet::%d,server,nowait"
        args=[inst[:instance_spec][:memory_size],
              inst[:instance_spec][:cpu_cores],
              inst[:uuid],
              inst[:runtime_config][:vnc_port],
              hc.os_devpath,
              File.expand_path('kvm.pid', hc.inst_data_dir),
              inst[:runtime_config][:telnet_port]
             ]
        if vnic = inst[:instance_nics].first
          cmd += " -net nic,macaddr=%s -net tap,ifname=%s,script=,downscript="
          args << vnic[:mac_addr].unpack('A2'*6).join(':')
          args << vnic[:uuid]
        end
        sh(cmd, args)

        unless vnic.nil?
          sh("/sbin/ifconfig %s 0.0.0.0 up", [vnic[:uuid]])
          sh("/usr/sbin/brctl addif %s %s", [hc.bridge_if, vnic[:uuid]])
        end

        sleep 1
      end

      def terminate_instance(hc)
        kvm_pid=`pgrep -u root -f vdc-#{hc.inst_id}`
        if $?.exitstatus == 0 && kvm_pid.to_s =~ /^\d+$/
          sh("/bin/kill #{kvm_pid}")
        else
          logger.error("Can not find the KVM process. Skipping: kvm -name vdc-#{hc.inst_id}")
        end
      end

      def reboot_instance(hc)
        inst = hc.inst
        connect_monitor(inst[:runtime_config][:telnet_port]) { |t|
          t.cmd("system_reset")
        }
      end

      def attach_volume_to_guest(hc)
        # pci_devddr consists of three hex numbers with colon separator.
        #  dom <= 0xffff && bus <= 0xff && val <= 0x1f
        # see: qemu-0.12.5/hw/pci.c
        # /*
        # * Parse [[<domain>:]<bus>:]<slot>, return -1 on error
        # */
        # static int pci_parse_devaddr(const char *addr, int *domp, int *busp, unsigned *slotp)
        pci_devaddr = nil
        inst = hc.inst

        sddev = File.expand_path(File.readlink(hc.os_devpath), '/dev/disk/by-path')
        connect_monitor(inst[:runtime_config][:telnet_port]) { |t|
          # success message:
          #   OK domain 0, bus 0, slot 4, function 0
          # error message:
          #   failed to add file=/dev/xxxx,if=virtio
          c = t.cmd("pci_add auto storage file=#{sddev},if=scsi")
          # Note: pci_parse_devaddr() called in "pci_add" uses strtoul()
          # with base 16 so that the input is expected in hex. however
          # at the result display, void pci_device_hot_add_print() uses
          # %d for showing bus and slot addresses. use hex to preserve
          # those values to keep consistent.
          if c =~ /\nOK domain ([0-9a-fA-F]+), bus ([0-9a-fA-F]+), slot ([0-9a-fA-F]+), function/m
            # numbers in OK result is decimal. convert them to hex.
            pci_devaddr = [$1, $2, $3].map{|i| i.to_i.to_s(16) }
          else
            raise "Error in qemu console: #{c}"
          end

          # double check the pci address.
          c = t.cmd("info pci")

          # static void pci_info_device(PCIBus *bus, PCIDevice *d)
          # called in "info pci" gets back PCI bus info with %d.
          if c.split(/\n/).grep(/^\s+Bus\s+#{pci_devaddr[1].to_i(16)}, device\s+#{pci_devaddr[2].to_i(16)}, function/).empty?
            raise "Could not find new disk device attached to qemu-kvm: #{pci_devaddr.join(':')}"
          end
        }
        pci_devaddr.join(':')
      end

      def detach_volume_from_guest(hc)
        inst = hc.inst
        vol = hc.vol
        pci_devaddr = vol[:guest_device_name]

        connect_monitor(inst[:runtime_config][:telnet_port]) { |t|
          t.cmd("pci_del #{pci_devaddr}")
          #
          #  Bus  0, device   4, function 0:
          #    SCSI controller: PCI device 1af4:1001
          #      IRQ 0.
          #      BAR0: I/O at 0x1000 [0x103f].
          #      BAR1: 32 bit memory at 0x08000000 [0x08000fff].
          #      id ""
          c = t.cmd("info pci")
          pci_devaddr = pci_devaddr.split(':')
          unless c.split(/\n/).grep(/\s+Bus\s+#{pci_devaddr[1].to_i(16)}, device\s+#{pci_devaddr[2].to_i(16)}, function/).empty?
            raise "Detached disk device still be attached in qemu-kvm: #{pci_devaddr.join(':')}"
          end
        }
      end

    end
  end
end