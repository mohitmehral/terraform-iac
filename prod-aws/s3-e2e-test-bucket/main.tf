terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  cloud {
    organization = "marsmovers"
    workspaces { name = "prod-aws" }
  }
}

provider "aws" { region = "us-east-1" }

resource "aws_s3_bucket" "this" {
  bucket = "e2e-test-bucket"
  tags   = { ManagedBy = "terraform", CreatedBy = "openclaw" }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_arn" { value = aws_s3_bucket.this.arn }
