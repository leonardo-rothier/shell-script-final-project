#!/bin/bash

function print_color() {
    NC='\033[0m'
    color=$1

    case $color in 
        "green") COLOR='\033[0;32m' ;;
        "red") COLOR='\033[0;31m' ;;
        "*") COLOR=$NC ;;
    esac

    echo -e "$COLOR $2 $NC"
}

function is_service_active() {
    is_active=$(sudo systemctl is-active $1)

    if [ $is_active = "active" ]
    then
        return 0 #true  is the oposite of c 
    else
        return 1 #false
    fi
}

function print_service_status() {
    is_active=$(sudo systemctl is-active $1)

    if [ $is_active = "active" ]
    then
        echo "$1 is active and running"
    else
        echo "$1 is not active/running"
    fi
}

function is_firewall_rule_configured() {
    firewalld_ports=$(sudo firewall-cmd --list-all --zone=public | grep ports)
    port=$1

    if [[ $firewalld_ports = *$port* ]]
    then
        return 0  #true
    else
        return 1 #false
    fi
}

function verify_web_itens() {
    if [[ $1 = *$2* ]]
    then
        print_color "green" "Item $2 is present on the web page"
    else
        print_color "red" "Item $2 is not present on the web page"
    fi
}


if ! is_service_active firewalld
then 
    print_color "green" "Installing FirewallD... "
    sudo yum install firewalld -y
    
    print_color "green" "Starting FirewallD.. "
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
fi
print_service_status firewalld

# Configure database

if ! is_service_active mariadb-server
then
    print_color "green" "Installing MariaDB.. "
    sudo yum install mariadb-server -y

    print_color "green" "Starting MariaDB.. "
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
fi
print_service_status mariadb

# configure Firewall rule for Database
if ! is_firewall_rule_configured 3306
then
    print_color "green" "Configuring firewallD rule for Database"
    sudo firewall-cmd --zone=public --permanent --add-port=3306/tcp
    sudo firewall-cmd --reload
fi

# Configure database
cat > mariadb-setup.sql <<-EOF
CREATE DATABASE ecomdb;
CREATE USER "ecomuser"@"localhost" IDENTIFIED BY "ecompassword";
GRANT ALL PRIVILEGES ON ecomdb.* TO "ecomuser"@"localhost";
FLUSH PRIVILEGES;
EOF

print_color "green" "Setting up the database..."
sudo mysql < mariadb-setup.sql

# Create the load script
cat > db-load-script.sql <<-EOF
USE ecomdb;
CREATE TABLE products (id mediumint(8) unsigned NOT NULL auto_increment,Name varchar(255) default NULL,Price varchar(255) default NULL, ImageUrl varchar(255) default NULL,PRIMARY KEY (id)) AUTO_INCREMENT=1;

INSERT INTO products (Name,Price,ImageUrl) VALUES ("Laptop","100","c-1.png"),("Drone","200","c-2.png"),("VR","300","c-3.png"),("Tablet","50","c-5.png"),("Watch","90","c-6.png"),("Phone Covers","20","c-7.png"),("Phone","80","c-8.png"),("Laptop","150","c-4.png");
EOF

print_color "green" "Loading product table and its inventory..."
sudo mysql < db-load-script.sql

mysql_db_result=$(sudo mysql -e "USE ecomdb; SELET * FROM products;")

if [ -n mysql_db_result ]
then 
    print_color "green" "Table created with success!"
else
    print_color "reed" "Error on the creation of the products table"
fi

if  ! is_service_active httpd
then
    print_color "green" "Intalling httpd php libs..."
    sudo yum install -y httpd php php-mysqlnd

    #set env
    sudo sed -i 's/variables_order = *.*/variables_order = "EGPCS"/' /etc/php.ini
    sudo tee /etc/httpd/conf.d/ecom.conf > /dev/null <<EOF
    <VirtualHost *:80>
        DocumentRoot /var/www/ecom

        SetEnv DB_HOST "localhost"
        SetEnv DB_USER "ecomuser"
        SetEnv DB_PASSWORD "ecompassword"
        SetEnv DB_NAME "ecomdb"

        <Directory /var/www/ecom>
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
EOF

    # change html to php
    sudo sed -i "s/index.html/index.php/g" /etc/httpd/conf/httpd.conf

    print_color "green" "Starting httpd..."
    sudo systemctl start httpd
    sudo systemctl enable httpd
fi

if ! is_firewall_rule_configured 80
then 
    print_color "green" "Configuring firwallD rule for apache..."
    sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
    sudo firewall-cmd --reload
fi

# installing git
print_color "green" "Installing Git..."
sudo yum install git -y

# Get application from git
print_color "green" "Setting up php application..."
sudo mkdir -p /var/www/ecom/
sudo git clone https://github.com/leonardo-rothier/learning-app-ecommerce /var/www/ecom/

# check if products are on website
website=$(curl http://localhost)

products=$(sudo mysql -e "USE ecomdb; SELECT Name FROM products;" | sed 1d)

for item in $products
do
    verify_web_itens "$website" $item
done