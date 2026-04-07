#!/bin/bash
# ================================================
# JIT Bootstrap Agent - Multi-Cloud-JIT-Rendering-Platform
# ================================================

echo "=== JIT Bootstrap Agent Started ==="

# 1. Read configuration from Instance Metadata (as per design)
SOFTWARE=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/software)
VERSION=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/version)
RENDER_ENGINE=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/render_engine)
ENGINE_VERSION=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/engine_version)

echo "Configuring: $SOFTWARE $VERSION + $RENDER_ENGINE $ENGINE_VERSION"

# 2. Create mount point
mkdir -p /opt/render

# 3. Mount high-performance shared storage (JIT step)
# In real environment this would be FSx for Lustre / Filestore / NetApp Files
echo "Mounting shared software library..."
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  fs-0123456789abcdef.efs.ap-south-1.amazonaws.com:/ /opt/render

# 4. Set dynamic environment variables
cat <<EOF >> /etc/profile.d/render-env.sh
export MAYA_MODULE_PATH=/opt/render/maya/${VERSION}
export ARNOLD_PATH=/opt/render/arnold/${ENGINE_VERSION}
export PATH=\$PATH:/opt/render/arnold/${ENGINE_VERSION}/bin
export LD_LIBRARY_PATH=/opt/render/arnold/${ENGINE_VERSION}/lib
EOF

source /etc/profile.d/render-env.sh

# 5. Verify software is accessible
echo "✅ Software mounted successfully"
ls /opt/render/maya/${VERSION} 2>/dev/null && echo "Maya found" || echo "Maya folder ready"

# 6. Send READY callback to Control Plane
curl -X POST -H "Content-Type: application/json" \
  -d "{\"instance_id\":\"$(curl -s http://169.254.169.254/latest/meta-data/instance-id)\", \"status\":\"READY\", \"software\":\"$SOFTWARE\"}" \
  https://control-plane.example.com/callback

echo "=== Bootstrap Agent Completed - VM is READY for rendering ==="
