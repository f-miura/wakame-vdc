Feature: Host Node API

  Scenario: Create, update and delete for new host node with specified UUID

    When we make an api create call to host_nodes with the following options
      | account_id  | uuid     | node_id   | arch   | hypervisor | offering_cpu_cores | offering_memory_size |
      | a-shpoolxx  | hn-test1 | hva.demo1 | x86_64 | kvm        | 10                 | 1000                 |
    Then the previous api call should be successful
      And from the previous api call take {"uuid":} and save it to <registry:uuid>
      And the previous api call should have {"uuid":} equal to hn-test1

    When we make an api get call to host_nodes/hn-test1 with no options
    Then the previous api call should be successful
      And the previous api call should have {"uuid":} equal to hn-test1
      And the previous api call should have {"node_id":} equal to hva.demo1
      And the previous api call should have {"arch":} equal to x86_64
      And the previous api call should have {"hypervisor":} equal to kvm
      And the previous api call should have {"offering_cpu_cores":} equal to 10
      And the previous api call should have {"offering_memory_size":} equal to 1000

    When we make an api delete call to host_nodes/hn-test1 with no options
    Then the previous api call should be successful
