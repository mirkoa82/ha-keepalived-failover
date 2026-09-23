Home Assistant Active/Passive Failover Add-on
A Home Assistant OS add-on for an active/passive Home Assistant failover setup using a virtual IP address (VIP).

The add-on is intended to run on a backup Home Assistant OS node (for example, a Raspberry Pi). It monitors a primary Home Assistant node and, if the primary becomes unavailable, it assigns the VIP to the backup node and starts the backup Home Assistant Core instance. When the primary becomes stable again, the backup stops its Core instance and releases the VIP.

Warning: This project changes IP addressing and starts/stops Home Assistant Core. Test it carefully on your own network before relying on it for production use. A short IP-address overlap during automatic failback may occur if the primary node has the same VIP configured persistently.

Architecture
Example topology:

text
Primary Home Assistant OS node
  Node/management IP: 10.14.0.237
  Virtual service IP: 10.14.0.246

Backup Home Assistant OS node (Raspberry Pi)
  Node/management IP: assigned by your network
  Virtual service IP: 10.14.0.246 only during failover
Clients should normally use the virtual service IP:

text
http://10.14.0.246:8123
The backup node monitors the primary node IP and TCP port 8123. It does not monitor the VIP, because the backup owns that address during a failover.

Behavior
Normal operation
The primary Home Assistant node owns the VIP.

The backup add-on is running.

The backup Home Assistant Core is stopped when the primary is healthy.

The backup retains its own management IP, which can be used for Observer or host-level access.

Automatic failover
When the primary fails the configured number of health checks and remains unavailable through the configured grace period, the backup node:

Adds the virtual IP to the active network interface.

Sends gratuitous ARP announcements for the VIP.

Starts Home Assistant Core on the backup node.

Keeps the VIP while Core is starting.

Marks the failover as active once TCP port 8123 becomes available locally.

Automatic failback
When the primary is reachable and its TCP port 8123 has been stable for the configured number of checks plus the grace period, the backup node:

Stops its local Home Assistant Core.

Removes the virtual IP from the backup interface.

Returns to standby.

The backup intentionally stops Core before releasing the VIP during ordinary failback, reducing the period in which both nodes could serve Home Assistant.

Requirements
Home Assistant OS on the backup node.

The add-on runs with host networking and NET_ADMIN / NET_RAW privileges.

The backup node must be on the same Layer-2 network as the primary and the VIP.

The primary node must be reachable through its dedicated node IP.

A virtual IP must be reserved for this setup and must not be used by another device.

Home Assistant Supervisor API access is enabled for the add-on.

Installation
Add this GitHub repository to the Home Assistant Add-on Store.

Install HA Keepalived Failover on the backup Home Assistant OS node.

Configure the primary node IP, virtual IP, and timeouts.

Start the add-on.

Test the VIP safely with test_vip_only: true before enabling real failover.

Configuration
Example configuration:

text
master_node_ip: "10.14.0.237"
virtual_ip: "10.14.0.246"
prefix_length: 24

# "auto" detects the network interface from the IPv4 default route.
# You may specify an interface name manually if required.
interface: "auto"

# Set to true only while troubleshooting.
# When false, the add-on writes only important events and errors.
debug_logging: false

check_interval: 5
ping_timeout: 2
tcp_timeout: 3

failover_failures: 6
failover_grace_period: 30

failback_successes: 24
failback_grace_period: 30

core_start_timeout: 300
core_stop_timeout: 120

post_vip_add_delay: 3
post_vip_remove_delay: 3

# Safe, one-time test: add the VIP, wait, remove it, then exit.
test_vip_only: false
vip_test_duration: 10
Configuration reference
Option	Description
master_node_ip	Dedicated IP address of the primary Home Assistant node. The add-on checks ICMP and TCP port 8123 on this address.
virtual_ip	Virtual service IP moved to the backup node during failover.
prefix_length	IPv4 network prefix length, for example 24 for a /24 subnet.
interface	auto uses the interface associated with the IPv4 default route. Set a specific interface only when required.
debug_logging	Enables detailed periodic logs for troubleshooting. Keep false in normal standby operation to minimize log writes.
check_interval	Delay, in seconds, between primary health checks.
ping_timeout	ICMP ping timeout, in seconds.
tcp_timeout	TCP connection timeout for Home Assistant port 8123, in seconds.
failover_failures	Consecutive failed checks required before beginning failover.
failover_grace_period	Additional wait before acquiring the VIP after the failover threshold is reached.
failback_successes	Consecutive successful checks required before beginning failback.
failback_grace_period	Additional wait before releasing the VIP after the failback threshold is reached.
core_start_timeout	Maximum wait for the backup Core to become reachable on TCP port 8123.
core_stop_timeout	Maximum wait for the backup Core to stop.
post_vip_add_delay	Delay after adding the VIP before starting Core.
post_vip_remove_delay	Delay after removing the VIP before completing failback.
test_vip_only	Enables a non-destructive VIP add/remove test. It does not start/stop Core or alter the primary node.
vip_test_duration	Number of seconds that the VIP remains assigned during the VIP-only test.
Interface detection
With interface: auto, the add-on identifies the active interface from the IPv4 default route. For example:

text
default via 10.14.0.1 dev end0
In this case it uses end0. This avoids hard-coding a device name such as eth0 or a backup node IP address.

If your host has multiple active network interfaces, policy routing, or multiple default gateways, set the interface explicitly after testing:

text
interface: "end0"
Logging
Normal standby monitoring should not continuously write log lines to storage. With:

text
debug_logging: false
the add-on logs startup, errors, state transitions, failover/failback actions, VIP changes, and Core start/stop actions, but it does not log each successful standby health probe.

For troubleshooting, temporarily use:

text
debug_logging: true
After testing, set it back to false.

Testing safely
1. Test the virtual IP only
Before running a failover test, use:

text
test_vip_only: true
vip_test_duration: 10
The add-on will:

Add the VIP to the backup network interface.

Verify that it is present.

Send gratuitous ARP announcements when arping is available.

Wait for the configured duration.

Remove the VIP.

Verify that it is absent and exit.

This test does not start or stop Home Assistant Core and does not change the primary node.

2. Test failover
For a controlled test, use temporarily short values such as:

text
check_interval: 2
failover_failures: 2
failover_grace_period: 5
failback_successes: 3
failback_grace_period: 5
core_start_timeout: 300
core_stop_timeout: 120
Then stop the primary node or deliberately make its dedicated IP unavailable. Confirm that the backup acquires the VIP and that Home Assistant is reachable through it.

3. Test failback
Restore the primary node and wait for the configured number of healthy checks and the grace period. Confirm that the backup stops Core and removes the VIP.

ARP and failback note
During failover, the backup sends gratuitous ARP announcements to inform LAN clients that the VIP now maps to the backup MAC address.

On failback, some clients may retain the backup MAC address in their ARP cache until the entry expires or is refreshed. If a client cannot reach the VIP immediately after failback, clear its ARP entry or configure the primary node to send gratuitous ARP announcements for the VIP.

On macOS, for example:

bash
sudo arp -d 10.14.0.246
A robust production setup should also arrange for the primary node to announce the VIP when it returns to service.

Access when Core is stopped
When the backup Core is stopped, the normal Home Assistant user interface at port 8123 is unavailable. The backup host and Supervisor remain active.

Useful access paths include:

Observer: http://<backup-node-ip>:4357

Home Assistant OS debug SSH: port 22222, key-based authentication

Local console with HDMI and USB keyboard

Observer is useful for health information but is not a full management UI or shell.

Important limitations
This add-on is not a distributed Home Assistant cluster: the two Core instances do not automatically synchronize configuration, database, add-on state, Zigbee/Z-Wave radios, or integrations.

Do not allow both nodes to actively control the same devices unless you understand the consequences.

Automatic failback can briefly create a duplicate-IP condition if the primary node automatically restores the same VIP before the backup releases it.

A power loss or host crash cannot run the add-on cleanup routine; the VIP disappears naturally when the backup network interface goes down.

Do not expose Observer or SSH services directly to the public internet.

Recommended production timing
A conservative starting point is:

text
check_interval: 5
failover_failures: 6
failover_grace_period: 30
failback_successes: 24
failback_grace_period: 30
core_start_timeout: 300
core_stop_timeout: 120
This creates approximately 60 seconds of failure detection before failover, plus backup Core startup time. Failback requires approximately 150 seconds of stable primary health, plus shutdown and network convergence time.

License and contributions
This is a community project. Please test carefully, report issues with sanitized logs and network topology details, and contribute improvements through pull requests.
