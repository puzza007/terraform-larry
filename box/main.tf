terraform {
  required_providers {
    oci = {
      source  = "hashicorp/oci"
      version = "4.37.0"
    }
  }
}

locals {
  shape = "VM.Standard.A1.Flex"
}

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.compartment_id
  ad_number      = 1
}

resource "oci_core_vcn" "vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_id
  display_name   = "${var.name}_vcn"
  dns_label      = var.name
}

resource "oci_core_internet_gateway" "ig" {
  compartment_id = var.compartment_id
  display_name   = "${var.name}_ig"
  vcn_id         = oci_core_vcn.vcn.id
}

resource "oci_core_default_route_table" "route_table" {
  manage_default_resource_id = oci_core_vcn.vcn.default_route_table_id
  display_name               = "${var.name}_rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ig.id
  }
}

resource "oci_core_subnet" "subnet" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  cidr_block          = "10.1.20.0/24"
  display_name        = "${var.name}_subnet"
  dns_label           = var.name
  security_list_ids   = [oci_core_vcn.vcn.default_security_list_id]
  compartment_id      = var.compartment_id
  vcn_id              = oci_core_vcn.vcn.id
  route_table_id      = oci_core_vcn.vcn.default_route_table_id
  dhcp_options_id     = oci_core_vcn.vcn.default_dhcp_options_id
}

data "oci_core_images" "list" {
  compartment_id   = var.compartment_id
  operating_system = "Canonical Ubuntu"
  shape            = local.shape
  state            = "AVAILABLE"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
}

resource "oci_core_instance" "instance" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_id

  display_name = var.name

  shape = local.shape
  shape_config {
    ocpus         = var.cpus
    memory_in_gbs = var.ram
  }

  source_details {
    boot_volume_size_in_gbs = var.hdd
    source_type             = "image"
    source_id               = data.oci_core_images.list.images[0].id
  }

  create_vnic_details {
    assign_public_ip = true
    subnet_id        = oci_core_subnet.subnet.id
  }

  metadata = {
    user_data = base64encode(templatefile("${path.module}/bootstrap.sh", {
      ssh_key          = var.ssh_key,
    }))
  }

}
