data "aws_instance" "web" {
    filter {
        name = "tag:Name"
        values = ["DevopsMail-Web-Server"]
    }
    filter {
    name   = "instance-state-name"
    values = ["running"]
  }

}

resource "aws_cloudwatch_dashboard" "devopsmail" {
    dashboard_name = "DevOpsMail-Monitoring"

    dashboard_body = jsonencode({
        widgets = [
            #CPU Util
            {
                type = "metric"
                x = 0
                y = 0
                width = 12
                height = 6
                properties = {
                    metrics = [
                        ["AWS/EC2", "CPUUtilization", "InstanceId", data.aws_instance.web.id]
                    ]
                    period = 300
                    region = "us-east-1"
                    title = "EC2 CPU Utilization"
                    view = "timeSeries"
                    stacked = false
                }
            },

            #HTTP Access
            {
                type = "log"
                x = 0
                y = 6
                width = 12
                height = 6
                properties = {
                    query = "SOURCE '/aws/ec2/DevopsMail-Web-Server' | fields @timestamp, @message | sort @timestamp desc | limit 50"
                    region = "us-east-1"
                    title = "HTTP Access Logs" 
                }
            }
        ]
    })
}