
variable "aws_access_key_id" { default = "aws_access_key_id"}
variable "aws_secret_key" { default = "aws_secret_key" }
variable "bucket_name" { default = "bucket_name" }

variable "params" {
  type = "map"
  default = {
    aws_access_key_id = ""
    aws_secret_key = ""
    bucket_name = ""
  }
}

variable "number_of_instances" {
  description = "Number of instances to create and attach to ELB"
  default     = 1
}

provider "aws" {
 access_key = "${lookup(var.params,var.aws_access_key_id)}"
 secret_key = "${lookup(var.params,var.aws_secret_key)}"
 region = "ap-southeast-2"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_security_group" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
  name   = "default"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  filter {
    name = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name = "owner-alias"
    values = ["amazon"]
  }
}



resource "aws_launch_configuration" "test_conf" {
  name          = "web_config"
  image_id        = "${data.aws_ami.amazon_linux.id}"
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.test_profile.name}"
  security_groups = ["${data.aws_security_group.default.id}"]
  user_data = <<EOF
echo "test ... " > testdata.txt
EOF
}

resource "aws_autoscaling_group" "test_asg" {
  name                 = "test_asg"
  launch_configuration = "${aws_launch_configuration.test_conf.name}"
  availability_zones = ["ap-southeast-2a","ap-southeast-2b","ap-southeast-2c"]
  min_size             = 1
  max_size             = 2
  target_group_arns = ["${aws_alb_target_group.test_target_group.arn}"]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "test_security" {
  name = "test_security"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_alb" "test_alb" {
  name               = "test-alb"
  subnets         = ["${data.aws_subnet_ids.all.ids}"]
  security_groups = ["${data.aws_security_group.default.id}"]
  internal        = false
}

resource "aws_alb_listener" "test_listener" {
  load_balancer_arn = "${aws_alb.test_alb.arn}"
  port           = "80"
  protocol       = "HTTP"
  default_action {    
    target_group_arn = "${aws_alb_target_group.test_target_group.arn}"
    type             = "forward"  
  }
}

resource "aws_alb_listener_rule" "test_listener_rule" {
  depends_on   = ["aws_alb_target_group.test_target_group"]
  listener_arn = "${aws_alb_listener.test_listener.arn}"
  action {
    type             = "forward"
    target_group_arn = "${aws_alb_target_group.test_target_group.id}"
  }
  condition {    
    field  = "path-pattern"    
    values = ["*"]  
  }
}

resource "aws_alb_target_group" "test_target_group" {
  name     = "test-target-group"
  port     = "80"
  protocol = "HTTP"
  vpc_id   = "${data.aws_vpc.default.id}"
  tags {
    name = "test-target-group"
  }
}

resource "aws_autoscaling_attachment" "test_autoscaling_attachment" {
  alb_target_group_arn   = "${aws_alb_target_group.test_target_group.arn}"
  autoscaling_group_name = "${aws_autoscaling_group.test_asg.id}"
}

resource "aws_iam_role" "test_role" {
  name = "test-role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }]
}
EOF
}

resource "aws_iam_instance_profile" "test_profile" {
  name = "test-profile"
  role = "${aws_iam_role.test_role.name}"
}

resource "aws_iam_role_policy" "test_policy" {
  name = "test-policy"
  role = "${aws_iam_role.test_role.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
       "Action": ["s3:*"],
       "Effect": "Allow",
       "Resource": [
         "arn:aws:s3:::${lookup(var.params,var.bucket_name)}",
         "arn:aws:s3:::${lookup(var.params,var.bucket_name)}/*"
       ]
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "arn:aws:s3:::*"
    }]
}
EOF
}

resource "aws_s3_bucket" "test-bucket" {
  bucket = "${lookup(var.params,var.bucket_name)}"
  acl = "private"
  tags {
    name = "test-bucket"
  }
}
