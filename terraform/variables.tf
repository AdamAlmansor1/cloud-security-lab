variable "aws_region" {
  description = "AWS region"
  type = string
  default = "ap-southeast-2"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type = string
  default = "ap-southeast-2a"
}


variable "app_key_name" {
  description = "Name of the key pair for the application server"
  type = string
  default = "app-key"
}

variable "project" {
  description = "Project name"
  type = string
  default = "cloud_soc"
}