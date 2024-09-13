resource "aws_wafv2_ip_set" "nul_staff_ip_set" {
  name               = "nul-staff-ips"
  description        = "NU Library Staff IPv4 Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.nul_staff_ips
  tags               = local.tags
}

resource "aws_wafv2_ip_set" "nul_ip_set" {
  name               = "nul-ips"
  description        = "NU Library IPv4 Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.nul_ips.v4
  tags               = local.tags
}

resource "aws_wafv2_ip_set" "nul_ipv6_set" {
  name               = "nul-ips-v6"
  description        = "NU Library IPv6 Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = var.nul_ips.v6
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

resource "aws_wafv2_ip_set" "high_traffic_ips_aug2024" {
  name               = "high-traffic-ips-AUG2024"
  description        = "High Traffic IPs added by Marek August 2024"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.high_traffic_ips_aug2024
  tags               = local.tags
}
