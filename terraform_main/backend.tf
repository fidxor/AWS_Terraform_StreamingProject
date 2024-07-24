terraform {
  backend "s3" {
    bucket = "24kng-tfstate"
    key    = "terraform.tfstate"
    region = "ap-northeast-2"
  }
}