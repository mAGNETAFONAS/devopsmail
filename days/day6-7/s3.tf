resource "aws_s3_bucket" "devopsmail" {
    bucket = "devopsmail-simas-logs"

    tags = {
        Name = "DevOpsMail-S3-Bucket"
        Environment = "Learning"
    }
}

resource "aws_s3_bucket_public_access_block" "devopsmail" {
    bucket = aws_s3_bucket.devopsmail.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "devopsmail" {
    bucket = aws_s3_bucket.devopsmail.id

    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_lifecycle_configuration" "devopsmail" {
    bucket = aws_s3_bucket.devopsmail.id

    rule {
        id = "transition-to-ia"
        status = "Enabled"

        transition {
            days = 30
            storage_class = "STANDARD_IA"
        }

        transition {
            days = 90
            storage_class = "GLACIER_IR"
        }

        expiration {
            days = 365
        }
    }
}