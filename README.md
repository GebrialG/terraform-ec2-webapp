# terraform-ec2-webapp

A highly available web app on AWS built with Terraform: two nginx
instances across two Availability Zones behind an Application Load Balancer.


                        Internet
                           |
                  [ Internet Gateway ]
                           |
   +-----------------------+------------------------+
   |  VPC 10.0.0.0/16                                |
   |                                                 |
   |   Public subnet A            Public subnet B    |
   |   10.0.1.0/24 (AZ a)         10.0.2.0/24 (AZ b) |
   |   +---------------+          +---------------+ |
   |   |  EC2 + nginx  |          |  EC2 + nginx  | |
   |   +---------------+          +---------------+ |
   |           ^                          ^          |
   |           +----------+---------------+          |
   |                      |                          |
   |        [ Application Load Balancer ]            |
   |        (listens on port 80, spans both AZs)     |
   +-------------------------------------------------+
Traffic flow: 

A browser sends a request to the ALB’s DNS name, the ALB picks a healthy instance, and the instance answers with an HTML page showing its own instance ID. The instances only accept traffic from the ALB, never directly from the internet.
