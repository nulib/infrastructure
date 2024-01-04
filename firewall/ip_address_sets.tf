resource "aws_wafv2_ip_set" "nul_ip_set" {
  name               = "nul-ips"
  description        = "NU Library IPv4 Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.nul_ips
  tags               = local.tags
}

resource "aws_wafv2_ip_set" "nul_ipv6_set" {
  name               = "nul-ips-v6"
  description        = "NU Library IPv6 Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = local.nul_ips_v6
  tags               = local.tags
}

resource "aws_wafv2_ip_set" "high_traffic_ip_set" {
  name               = "high-traffic-ips"
  description        = "High Traffic IPs"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.high_traffic_ips
  tags               = local.tags
}
