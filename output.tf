output "external_ip_address_bastion" {
  value = yandex_vpc_address.network2.external_ipv4_address.0.address
}

output "external_ip_address_zabbix" {
  value = yandex_compute_instance.zabbix.network_interface.0.nat_ip_address
}

output "external_ip_address_kibana" {
  value = yandex_compute_instance.kibana.network_interface.0.nat_ip_address
}

output "external_ip_address_loadbalancer" {
  value = yandex_alb_load_balancer.loadbalancer.listener.0.endpoint.0.address.0.external_ipv4_address
}
