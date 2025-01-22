#take from environment
variable "yandex_cloud_token" {}
variable "yandex_cloud_id" {}
variable "yandex_folder_id" {}

#ubuntu 22.04
variable "disk1" {
  default     = "fd83prfqnldo1u6hvmmg"
  description = "Ubuntu22 disk image"
}

variable "zone1" {
  default     = "ru-central1-a"
  description = "Yandex cloud zone1"
}

variable "zone2" {
  default     = "ru-central1-b"
  description = "Yandex cloud zone2"
}
