variable "vpc_id" {}
variable "subnets" {
  type = list(string)
}
variable "ami_id" {}
variable "instance_type" {
  default = "t3.micro"
}
variable "key_name" {}
variable "docker_image" {}
variable "codedeploy_role_arn" {}
