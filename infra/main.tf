resource "aws_s3_bucket" "test_bucket" {
  bucket        = "kunvar-anmol-devops-test-2026-unique"   # Change if taken
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.test_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
