#!/bin/bash
set -e

echo "Starting smart network setup..."

# Setup loopback
ip link set lo up

# Find and configure all network interfaces
configured=false
for iface in $(ls /sys/class/net | grep -v lo); do
    echo "Found interface: $iface"
    
    # Bring up the interface
    ip link set "$iface" up
    
    # Try to get IP via DHCP
    echo "Configuring $iface with DHCP..."
    
    # Try different DHCP clients in order of preference
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -v "$iface" && configured=true
    elif command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i "$iface" -n && configured=true
    elif command -v dhcpcd >/dev/null 2>&1; then
        dhcpcd "$iface" && configured=true
    else
        echo "No DHCP client found, trying to configure statically..."
        # For GCP, we can try to use the metadata server
        # The internal IP is usually 10.x.x.x with gateway at 10.x.x.1
        ip_addr=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -z "$ip_addr" ]; then
            # Fallback: try common private network ranges
            ip addr add 10.128.0.2/24 dev "$iface"
            ip route add default via 10.128.0.1 dev "$iface"
        fi
    fi
    
    # Check if we got an IP
    if ip -4 addr show "$iface" | grep -q "inet "; then
        echo "Successfully configured $iface"
        configured=true
        break
    fi
done

# Configure DNS if not already set
if [ ! -s /etc/resolv.conf ] || ! grep -q nameserver /etc/resolv.conf; then
    echo "Configuring DNS..."
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 169.254.169.254
EOF
fi

# Make resolv.conf immutable to prevent overwriting
chattr +i /etc/resolv.conf 2>/dev/null || true

if [ "$configured" = true ]; then
    echo "Network setup completed successfully"
    # Show network configuration
    ip addr show
    ip route show
    exit 0
else
    echo "Warning: Network configuration may be incomplete"
    exit 0  # Exit 0 to not block boot
fi