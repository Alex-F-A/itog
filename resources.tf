#--------------------------------------------------------------------------Net for netology
resource "yandex_vpc_network" "network1" {
  name = "network1-neto"
}
#--------------------------------------------------------------------------External net for bastion
resource "yandex_vpc_address" "network2" {
  name = "network2-external-ip"
  external_ipv4_address {
    zone_id = var.zone1
  }
}

#---------------------------------------------------------------------------Subnet 1 - main 
resource "yandex_vpc_subnet" "subnet1" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network1.id
  v4_cidr_blocks = ["10.1.1.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}
#---------------------------------------------------------------------------Subnet 2
resource "yandex_vpc_subnet" "subnet2" {
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.network1.id
  v4_cidr_blocks = ["10.1.2.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}

#-------------------------------------------------------------------------- Loadbalanser infrastructure start:
#-------------------------------------------------------------------------- target_group 
resource "yandex_alb_target_group" "web-target-group" {
  name = "web-target-group"

  target {
    ip_address = yandex_compute_instance.web1.network_interface.0.ip_address
    subnet_id  = yandex_vpc_subnet.subnet1.id
  }

  target {
    ip_address = yandex_compute_instance.web2.network_interface.0.ip_address
    subnet_id  = yandex_vpc_subnet.subnet2.id
  }
}

#-------------------------------------------------------------------------- backend_group
resource "yandex_alb_backend_group" "backendgroup" {
  name = "backendgroup"
  #session_affinity {
  #  connection {
  #    source_ip = <режим_привязки_сессий_по_IP-адресу>
  #  }
  #}
  http_backend {
    name             = "http-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web-target-group.id]
    load_balancing_config {
      panic_threshold = 0
    }
    healthcheck {
      timeout             = "10s"
      interval            = "2s"
      healthy_threshold   = 2
      unhealthy_threshold = 3
      http_healthcheck {
        path = "/"
      }
    }
  }
}

#--------------------------------------------------------------------------------http router
resource "yandex_alb_http_router" "http-router" {
  name = "http-router"
}

resource "yandex_alb_virtual_host" "virtual-host" {
  name           = "virtualhost"
  http_router_id = yandex_alb_http_router.http-router.id
  route {
    name = "route1"
    http_route {
      #      http_match {
      #        path {
      #          prefix = "/"
      #        }
      #      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backendgroup.id
        timeout          = "60s"
      }
    }
  }
}
#-------------------------------------------------------------------------- Loadbalanser infrastructure end

#----------------------------------------------------------------------------Loadbalanser
resource "yandex_alb_load_balancer" "loadbalancer" {
  name               = "loadbalancer"
  network_id         = yandex_vpc_network.network1.id
  security_group_ids = [yandex_vpc_security_group.local_sg.id, yandex_vpc_security_group.lb_sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.subnet1.id
    }
  }

  listener {
    name = "listener1"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.http-router.id
      }
    }
  }
}

#------------------------------------------------------------------------------nat
resource "yandex_vpc_gateway" "nat-gateway" {
  #  folder_id = "b1g78afq36tna7sv797c"
  name = "natgatewayw"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "rt" {
  #  folder_id = "b1g78afq36tna7sv797c"
  name       = "routetable"
  network_id = yandex_vpc_network.network1.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat-gateway.id
  }
}

#-----------------------------------------------------------------------------Security group (Begin)
#--------------------------------------------------------------------common rules for local net
resource "yandex_vpc_security_group" "local_sg" {
  name       = "local-security"
  network_id = yandex_vpc_network.network1.id

  ingress {
    protocol          = "ANY"
    description       = "Allow incoming traffic from members of the same security group"
    predefined_target = "self_security_group"
  }

  egress {
    protocol       = "ANY"
    description    = "Allow outgoing traffic to members of the same security group"
    v4_cidr_blocks = ["0.0.0.0/0"]
    #predefined_target = "self_security_group"
  }
}
#-------------------------------------------------------------rules for loadbalanser (external)
resource "yandex_vpc_security_group" "lb_sg" {
  name       = "lb-sg"
  network_id = yandex_vpc_network.network1.id

  ingress {
    protocol          = "ANY"
    description       = "Health checks"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    protocol       = "TCP"
    description    = "allow HTTP connections from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "allow outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
#--------------------------------------------------optional for websrv's, not in use
/*
resource "yandex_vpc_security_group" "web_sg" {
  name       = "local-balanser"
  network_id = yandex_vpc_network.network1.id

  ingress {
    description = "Allow HTTP for local subnets"
    protocol    = "TCP"
    #    port           = "80"
    v4_cidr_blocks = ["10.1.1.0/0", "10.1.2.0/0"]
  }

  ingress {
    description       = "Health checks from NLB"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    description    = "allow outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
*/
#-------------------------------------------------------------------rules for bastion
resource "yandex_vpc_security_group" "bastion_sg" {
  name       = "bastion-securuty"
  network_id = yandex_vpc_network.network1.id

  ingress {
    protocol       = "TCP"
    description    = "allow ssh"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "allow outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
#--------------------------------------------------------------------rules for zabbix (external)
resource "yandex_vpc_security_group" "zabbix_sg" {
  name       = "zabbix-security"
  network_id = yandex_vpc_network.network1.id

  ingress {
    protocol       = "TCP"
    description    = "allow http to zabbbix"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "allow outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
#--------------------------------------------------------------------rules for kibana (external)
resource "yandex_vpc_security_group" "kibana_sg" {
  name       = "kibana-security"
  network_id = yandex_vpc_network.network1.id

  ingress {
    protocol       = "TCP"
    description    = "allow http to kibana port"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }

  egress {
    protocol       = "ANY"
    description    = "allow outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
#-----------------------------------------------------------------------------Security group (end)

#-----------------------------------------------------------------------------Virtual machines (Begin)
#--------------------------------------------------------------------------------WEB1
resource "yandex_compute_disk" "web1_disk" {
  name     = "web1-disk"
  type     = "network-hdd"
  zone     = var.zone1
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "websrv"
  }
}

resource "yandex_compute_instance" "web1" {
  name        = "vm-web1"
  hostname    = "websrv1"
  platform_id = "standard-v1"
  zone        = var.zone1

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.web1_disk.id
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.subnet1.id
    ip_address = "10.1.1.11"
    #nat                = false
    security_group_ids = [yandex_vpc_security_group.local_sg.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#---------------------------------------------------------------------------------WEB2
resource "yandex_compute_disk" "web2_disk" {
  name     = "web2-disk"
  type     = "network-hdd"
  zone     = var.zone2
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "websrv"
  }
}

resource "yandex_compute_instance" "web2" {
  name        = "vm-web2"
  hostname    = "websrv2"
  platform_id = "standard-v1"
  zone        = var.zone2

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.web2_disk.id
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.subnet2.id
    ip_address = "10.1.2.11"
    #nat        = false
    security_group_ids = [yandex_vpc_security_group.local_sg.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#------------------------------------------------------------------------------Bastion
resource "yandex_compute_disk" "bastion_disk" {
  name     = "bastion-disk"
  type     = "network-hdd"
  zone     = var.zone1
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "bastionsrv"
  }
}

resource "yandex_compute_instance" "bastion" {
  name        = "vm-bastion"
  hostname    = "bastion"
  platform_id = "standard-v1"
  zone        = var.zone1

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.bastion_disk.id
  }

  #network_interface {
  #  subnet_id      = "e9btukjnsn9m0i89v845"
  #  nat            = true
  #  nat_ip_address = yandex_vpc_address.network2.external_ipv4_address[0].address
  #}

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet1.id
    ip_address         = "10.1.1.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.local_sg.id, yandex_vpc_security_group.bastion_sg.id]
    nat_ip_address     = yandex_vpc_address.network2.external_ipv4_address[0].address
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#--------------------------------------------------------------------------------Zabbix
resource "yandex_compute_disk" "zabbix_disk" {
  name     = "zabbix-disk"
  type     = "network-hdd"
  zone     = var.zone1
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "zabsrv"
  }
}

resource "yandex_compute_instance" "zabbix" {
  name        = "vm-zabbbix"
  hostname    = "zabbix"
  platform_id = "standard-v1"
  zone        = var.zone1

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.zabbix_disk.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet1.id
    ip_address         = "10.1.1.12"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.local_sg.id, yandex_vpc_security_group.zabbix_sg.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#--------------------------------------------------------------------------------Elastic
resource "yandex_compute_disk" "elastic_disk" {
  name     = "elastic-disk"
  type     = "network-hdd"
  zone     = var.zone1
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "elasticsrv"
  }
}

resource "yandex_compute_instance" "elastic" {
  name        = "vm-elastic"
  hostname    = "elastic"
  platform_id = "standard-v1"
  zone        = var.zone1

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.elastic_disk.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet1.id
    ip_address         = "10.1.1.13"
    nat                = false
    security_group_ids = [yandex_vpc_security_group.local_sg.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#--------------------------------------------------------------------------------kibana
resource "yandex_compute_disk" "kibana_disk" {
  name     = "kibana-disk"
  type     = "network-hdd"
  zone     = var.zone1
  image_id = var.disk1
  size     = "10"
  labels = {
    environment = "kibanasrv"
  }
}

resource "yandex_compute_instance" "kibana" {
  name        = "vm-kibana"
  hostname    = "kibana"
  platform_id = "standard-v1"
  zone        = var.zone1

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 5
  }

  boot_disk {
    disk_id = yandex_compute_disk.kibana_disk.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet1.id
    ip_address         = "10.1.1.14"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.local_sg.id, yandex_vpc_security_group.kibana_sg.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("./meta.txt")}"
  }
}

#-------------------------------------------------------------------------------------------Snapshots
resource "yandex_compute_snapshot_schedule" "defaultsnapshot" {
  schedule_policy {
    expression = "0 0 * * *"
  }

  retention_period = "168h"

  disk_ids = ["${yandex_compute_instance.web1.boot_disk.0.disk_id}",
    "${yandex_compute_instance.web2.boot_disk.0.disk_id}", "${yandex_compute_instance.zabbix.boot_disk.0.disk_id}",
  "${yandex_compute_instance.elastic.boot_disk.0.disk_id}", "${yandex_compute_instance.kibana.boot_disk.0.disk_id}"]

}

