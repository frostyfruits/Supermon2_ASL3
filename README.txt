After running supermon2_ASL3_install.sh

Open terminal and run

cat <<EOF | sudo tee /var/www/html/supermon2/.htaccess
DirectoryIndex index.php index.html
EOF
sudo systemctl reload apache2
