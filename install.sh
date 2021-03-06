#!/bin/bash

export COMPOSER_JSON="composer.json"
export DOWNLOAD_DIR="download"
export THEME_NAME="jupiter"
export THEME_FILENAME="jupiter.zip"
export USER_THEME_NAME="$THEME_NAME-child"

echo "================="
echo "Check Environment"
echo "================="

##### check required packages #####
if ! type "php" &> /dev/null; then
    echo "Could not find command php, install ..."
    sudo apt-get -y install php
fi

if ! type "unzip" &> /dev/null; then
    echo "Could not find command unzip, please install it first, install ..."
    sudo apt-get -y install unzip
fi

if ! type "composer" &> /dev/null; then
    echo "Could not find composer, install ... "
    curl -sS https://getcomposer.org/installer | php &> /dev/null
    mv composer.phar /usr/local/bin/composer
fi

##### get arguments from composer.json #####
export WP_DIR_NAME=`less $COMPOSER_JSON | grep -Po '(?<="webroot-dir": ")[^"]*'`
export WP_VERSION=`less $COMPOSER_JSON | grep -Po '(?<="wordpress": ")[^"]*'`

##### cleanup environment #####
if [ -d "vendor" ]; then
    echo "Removing vendor directory ... "
    rm -r vendor
fi

if [ -d $WP_DIR_NAME ]; then
    echo "Removing old install of WordPress ... "
    rm -r $WP_DIR_NAME
fi

##### install wordpress ######
echo "================="
echo "Install WordPress"
echo "================="

# run install
echo "Update composer dependencies ... "
composer update
echo "Install WordPress $WP_VERSION ... "
composer install

# check install result
if [ ! -d "$WP_DIR_NAME" ]; then
    echo "Could not find WordPress installation in $WP_DIR_NAME directory"
    exit 1
fi

# change folder owner
# www-data is for Ubuntu
id -u "www-data" &> /dev/null && chown -R www-data:www-data $WP_DIR_NAME
# add support for other OS if needed

# should we install optional theme?
INSTALL_THEME=true

##### install jupiter theme #####
if [ -z "$ENVATO_USERNAME" ]; then
    echo "Fail to find evnato username in environment variable, skip."
    INSTALL_THEME=false
fi

if [ -z "$ENVATO_API_KEY" ]; then
    echo "Fail to find evnato api key in environment variable, skip."
    INSTALL_THEME=false
fi

if [ -z "$ENVATO_PURCHASE_CODE" ]; then
    echo "Fail to find evnato purchase code for Jupiter Theme in environment variable, abort."
    INSTALL_THEME=false
fi
if [ "$INSTALL_THEME" = true ]; then
    echo "==============="
    echo "Download Themes"
    echo "==============="

    # here we get the response from the Envato APIs using curl library
    echo "Querying download URL for theme packages ... "
    response=`curl -s "http://marketplace.envato.com/api/edge/$ENVATO_USERNAME/$ENVATO_API_KEY/download-purchase:$ENVATO_PURCHASE_CODE.json"`
    if [ $? != 0 ]; then
        echo "Fail to get download URL from envota marketplace, abort."
        exit 1
    fi

    response_error=`echo $response | python -mjson.tool | grep -Po '(?<="error": ")[^"]*'`
    if [ "$response_error" != "" ]; then
        echo "Fail to get download URL from envota marketplace, reason: $response_error"
        exit 1
    fi

    response_url=`echo $response | python -mjson.tool | grep -Po '(?<="download_url": ")[^"]*'`

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        mkdir $DOWNLOAD_DIR
    else
        rm -r $DOWNLOAD_DIR/*
    fi

    echo "Downloading theme package from $response_url ... into direcotry $DOWNLOAD_DIR"
    wget $response_url -O $DOWNLOAD_DIR/$THEME_FILENAME
    if [ $? != 0 ]; then
        echo "Fail to download theme package from envota marketplace, abort."
        exit 1
    fi

    echo "======================================"
    echo "Install Themes (Tweak Based on Themes)"
    echo "======================================"

    echo "Extract downloaded archive ... "
    unzip -qq $DOWNLOAD_DIR/$THEME_FILENAME -d $DOWNLOAD_DIR
    if [ $? != 0 ]; then
        echo "Fail to unzip theme package file $DOWNLOAD_DIR/$THEME_FILENAME, abort."
        exit 1
    fi
    rm -rf $DOWNLOAD_DIR/$THEME_FILENAME

    echo "Extract theme content from package file ... "
    theme_package=`find . -name $THEME_FILENAME`
    unzip -qq $theme_package -d $DOWNLOAD_DIR
    if [ $? != 0 ]; then
        echo "Fail to unzip theme package file $theme_package, abort."
        exit 1
    fi

    ##### install parent theme #####
    cp -r $DOWNLOAD_DIR/$THEME_NAME $WP_DIR_NAME/wp-content/themes/$THEME_NAME
    chmod -R 755 $WP_DIR_NAME/wp-content/themes/$THEME_NAME

    ##### install child theme #####
    cp -r theme $WP_DIR_NAME/wp-content/themes/$USER_THEME_NAME
    chmod -R 755 $WP_DIR_NAME/wp-content/themes/$USER_THEME_NAME
fi

##### config WordPress ftp user account #####
echo "========================================================================================================================="
echo "Create a FTP user for WordPress"
echo "https://www.digitalocean.com/community/tutorials/how-to-configure-secure-updates-and-installations-in-wordpress-on-ubuntu"
echo "========================================================================================================================="

export WP_USER=wp-user

echo "Checking if user $WP_USER already exist ... "
id -u $WP_USER &> /dev/null
if [ $? == 0 ]; then
    echo "System already has a user called $WP_USER, skip creation"
else
    if ! type "adduser" &> /dev/null; then
        echo "Could not find command adduser, please follow the above tutorials and create user for WordPress by yourself."
    else
        ## Add a New User for WordPress
        adduser $WP_USER
        chown -R $WP_USER:$WP_USER $(dirname $0)

        # skip if user is not successfully created
        id -u $WP_USER &> /dev/null
        if [ $? == 0 ]; then
            ## Create SSH Keys for WordPress
            echo "Creating SSH key for user $WP_USER"
            su -c "ssh-keygen -t rsa -b 4096 -f /home/$WP_USER/wp_rsa" $WP_USER

            chown $WP_USER:www-data /home/$WP_USER/wp_rsa*
            chmod 0640 /home/$WP_USER/wp_rsa*

            mkdir /home/$WP_USER/.ssh
            chown $WP_USER:$WP_USER /home/$WP_USER/.ssh/
            chmod 0700 /home/$WP_USER/.ssh/

            cp /home/$WP_USER/wp_rsa.pub /home/$WP_USER/.ssh/authorized_keys
            chown $WP_USER:$WP_USER /home/$WP_USER/.ssh/authorized_keys
            chmod 0644 /home/$WP_USER/.ssh/authorized_keys

            ## Restrict Key Usage to Local Machine
            echo -n 'from="127.0.0.1" ' | cat - /home/$WP_USER/.ssh/authorized_keys > temp && mv temp /home/$WP_USER/.ssh/authorized_keys
        fi
    fi
fi

##### add lines to wp-config-sample.php #####
echo "==================="
echo "Configure WordPress"
echo "==================="

wp_config_sample="$WP_DIR_NAME/wp-config-sample.php"
if [ ! -f $wp_config_sample ]; then
    echo "Could not find wp-config-sample.php in $WP_DIR_NAME directory"
    exit 1
fi

wp_config_sample_new="$WP_DIR_NAME/wp-config-sample.new"
if [ -f $wp_config_sample_new ]; then
    rm $wp_config_sample_new
fi
touch $wp_config_sample_new

echo "Prepare wp-config-sample.php for installing themes ... "

cat $wp_config_sample | while read line
do
    echo "$line" | grep -q "Sets up WordPress vars and included files"
    if [ $? -eq 0 ]; then
        echo "/***** The followings are automatically generated content *****/" >> $wp_config_sample_new
        echo "/* Required by Jupiter Theme: Maximum Execution Time */" >> $wp_config_sample_new
        echo "set_time_limit(60);" >> $wp_config_sample_new
        echo "define('WP_MEMORY_LIMIT', '1024M');" >> $wp_config_sample_new

        # only add when $WP_USER exists
        id -u $WP_USER &> /dev/null
        if [ $? == 0 ]; then
            echo "/* Required by WordPress plugin installation */" >> $wp_config_sample_new
            echo "define('FTP_PUBKEY','/home/$WP_USER/wp_rsa.pub');" >> $wp_config_sample_new
            echo "define('FTP_PRIKEY','/home/$WP_USER/wp_rsa');" >> $wp_config_sample_new
            echo "define('FTP_USER','wp-user');" >> $wp_config_sample_new
            echo "define('FTP_PASS','');" >> $wp_config_sample_new
            echo "define('FTP_HOST','127.0.0.1:22');" >> $wp_config_sample_new
        fi

        echo "/***** End of automatically generated content *****/" >> $wp_config_sample_new
        echo "" >> $wp_config_sample_new
    fi
    echo "$line" >> $wp_config_sample_new
done

echo "Create new configuration at $wp_config_sample"
mv $wp_config_sample_new $wp_config_sample

##### finish install #####
echo "====================================================================="
echo "Install Completed!"
echo "Please activate the dream maker theme and required plugins in"
echo "WordPress admin console right after you run this installation script!"
echo "                                                         by Hao Zhang"
echo "====================================================================="
