// AWS public cloud to launch OS using Terraform

provider "aws" {
    region = "ap-south-1"
    profile = "onmission"
}


// Generates a secure private key and encodes it as PEM

resource "tls_private_key" "instance_key" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

// Generates a local file with the given content

resource "local_file" "key_gen" {
    filename = "i_am_key.pem"
}

// Provides an EC2 key pair resource

resource "aws_key_pair" "instance_key" {
  key_name   = "i_am_key"
  public_key = tls_private_key.instance_key.public_key_openssh  
}


// Provides an EC2 instance resource

resource "aws_instance"  "my_instance" {
    ami = "ami-0447a12f28fddb066"
    instance_type = "t2.micro"
    key_name =  aws_key_pair.instance_key.key_name
    security_groups =  [ "allow_http" ] 
  
connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.instance_key.private_key_pem
    host = aws_instance.my_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

tags = {
    Name = "LinuxWorld"
  }
}


output  "myvar" {
	value = aws_instance.my_instance.availability_zone
}


// Provides a security group resource

resource "aws_security_group" "allow_http" {
    name = "allow_http"
    description = "Allow TCP inbound traffic"
    vpc_id = "vpc-dcf3eeb4"


  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}


// Creates EBS volume 

resource "aws_ebs_volume" "ebs_volume" {
    availability_zone = aws_instance.my_instance.availability_zone
    size = 2

  tags = {
      Name = "my_ebs_volume"
  }
}

//Provides an AWS EBS Volume Attachment

resource "aws_volume_attachment" "ebs_att_vol" {
    device_name = "/dev/sdf"
    volume_id   = aws_ebs_volume.ebs_volume.id
    instance_id = aws_instance.my_instance.id
    force_detach = true
}


output  "my_ebss" {
    value = aws_ebs_volume.ebs_volume.id
}


output "myos_ip" {
    value = aws_instance.my_instance.public_ip
}


// Public IP in folder mypublicip 

resource "null_resource" "localnull444"  {
    provisioner "local-exec" {
        command = "echo  ${aws_instance.my_instance.public_ip} > mypublicip.txt"
    }
}


// mount volume to /var/www/html

resource "null_resource" "remotenull333"  {

  depends_on = [
      aws_volume_attachment.ebs_att_vol,
    ]


  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.instance_key.private_key_pem 
    host = aws_instance.my_instance.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Himjo/bonzovi.git /var/www/html/"
    ]
  }
}


// Provides a S3 bucket resource & pull image to bucket from GitHub repo

resource "aws_s3_bucket" "bonzovi-bucket" {
  bucket = "bonzovi-bucket"
  acl = "public-read"

  provisioner "local-exec" {
      command = "git clone https://github.com/Himjo/bonzovi bonzovi-worlds"
    }
  provisioner "local-exec" {
      when = destroy
      command = "echo Y | rmdir /s bonzovi-worlds"
    }
}

// Provides a S3 bucket object resource pull & image to bucket from GitHub repo

resource "aws_s3_bucket_object" "image-pull" {
    bucket = aws_s3_bucket.bonzovi-bucket.bucket
    key = "iiec-rise.jpg"
    source = "bonzovi-worlds/vimal-sir.jpg"
    acl = "public-read"
}


// Creates an Amazon CloudFront web distribution & using Cloudfront URL to  update in code in /var/www/html

locals {
    s3_origin_id = aws_s3_bucket.bonzovi-bucket.bucket
    image_url = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-pull.key}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    origin {
        domain_name = aws_s3_bucket.bonzovi-bucket.bucket_regional_domain_name
        origin_id = local.s3_origin_id

    s3_origin_config {
        origin_access_identity = "origin-access-identity/cloudfront/EF7ZNA5TBIT4M"
      }
    }

    enabled = true
    is_ipv6_enabled = true
    default_root_object = "index.php"

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id

    forwarded_values {
        query_string = false
    cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all" 
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 172800
    }

   restrictions {
       geo_restriction {
       restriction_type = "none"
     }
   }

    viewer_certificate {
        cloudfront_default_certificate = true
      }

    tags = {
        Name = "Web-CF-Distribution"
      }

    connection {
        type = "ssh"
        user = "ec2-user"
        private_key = tls_private_key.instance_key.private_key_pem 
        host = aws_instance.my_instance.public_ip
     }

    provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image-pull.key}'>\" >> /var/www/html/index.php",
            "EOF"
          ]
      }
   }

resource "null_resource" "localnull222"  {
    depends_on = [
    aws_cloudfront_distribution.s3_distribution,
   ]

    provisioner "local-exec" {
        command = "start chrome  ${aws_instance.my_instance.public_ip}"
      }
 }
