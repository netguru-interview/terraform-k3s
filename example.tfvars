# DNS Settings
create_zone        = "true"
domain             = "kloud-native.com"
digitalocean_token = "dummy"

node_count  = 2
k3s_version = "v1.18.9-rc1+k3s1"
cni         = "flannel"

# Openstack Credentials
# Create Public Cloud Project > Users & Roles > Add User > Set Password > Download OpenStack RC File
# Use the following map;
region      = "WAW1"
tenant_name = "dummy"
user_name   = "dummy"
password    = "dummy"
auth_url    = "https://auth.cloud.ovh.net/v3"

# OVH Credentials
# Get these here https://api.ovh.com/createToken/index.cgi?GET=/*&POST=/*&PUT=/*&DELETE=/*
application_key    = "dummy"
application_secret = "dummy"
consumer_key       = "dummy"
endpoint           = "ca.api.ovh.com"

ssh_pubkey_path = "<path_to>/.ssh/id_rsa.pub"
ssh_key_path    = "<path_to>/.ssh/id_rsa""
