resource "aws_instance" "app" {
    ami           = "ami-00839deb72faa8a04"
    instance_type = "t2.micro"
    subnet_id     = aws_subnet.public.id
    key_name      = var.app_key_name
    vpc_security_group_ids = [aws_security_group.app_sg.id]

    user_data = file("${path.module}/flask_nginx_setup.sh")

    iam_instance_profile        = aws_iam_instance_profile.cw_agent.name

    tags = {
        Name = "AppServer"
    }
}

resource "aws_key_pair" "app_key" {
    key_name   = var.app_key_name
    public_key = file("../app-key.pub")
}

data "aws_iam_policy_document" "cw_agent_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cw_agent" {
  name               = "${var.project}-cw-agent-role"
  assume_role_policy = data.aws_iam_policy_document.cw_agent_assume.json
}

resource "aws_iam_role_policy_attachment" "cw_agent_attach" {
  role       = aws_iam_role.cw_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "cw_agent" {
  name = "${var.project}-cw-agent-profile"
  role = aws_iam_role.cw_agent.name
}
