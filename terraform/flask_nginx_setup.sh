#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -x

# Update and install dependencies
yum update -y
yum install -y python3 python3-pip nginx openssl

# Install Flask system-wide and for ec2-user
/usr/bin/pip3 install flask
sudo -u ec2-user /usr/bin/pip3 install --user flask

# Create app directory and ensure ownership
mkdir -p /home/ec2-user/flask-app
chown -R ec2-user:ec2-user /home/ec2-user/flask-app

# Create Flask app
cat <<'EOF' > /home/ec2-user/flask-app/app.py
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from Flask behind Nginx!"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)
EOF

# Create systemd service with explicit PATH
cat <<'EOF' > /etc/systemd/system/flaskapp.service
[Unit]
Description=Flask App Service
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/flask-app
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="PYTHONPATH=/usr/lib/python3.9/site-packages"
ExecStart=/usr/bin/python3 /home/ec2-user/flask-app/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Flask service
systemctl daemon-reload
systemctl enable flaskapp
systemctl start flaskapp

# Setup SSL cert dir
mkdir -p /etc/nginx/ssl

# Create self-signed cert for nginx
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt \
  -subj "/C=AU/ST=NSW/L=Sydney/O=Company/CN=localhost"

# Write nginx config to reverse proxy to flask
cat <<'EOF' > /etc/nginx/nginx.conf
events {}

http {
    server {
        listen 80;
        server_name _;
        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }

    server {
        listen 443 ssl;
        server_name _;
        ssl_certificate /etc/nginx/ssl/selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

systemctl restart nginx
systemctl enable nginx

sudo yum install -y amazon-cloudwatch-agent

touch /var/log/nginx/access.log /var/log/nginx/error.log
chown nginx:nginx /var/log/nginx/*.log

cat <<'CFG' | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/nginx/error.log",  "log_group_name": "/nginx/error"  },
          { "file_path": "/var/log/nginx/access.log", "log_group_name": "/nginx/access" }
        ]
      }
    }
  }
}
CFG

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent