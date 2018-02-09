<p align="center">
  <img src="https://github.com/xEsk/BAMP/raw/master/BAMP/Resources/Assets.xcassets/AppIcon.appiconset/fondo_128.png"/>
</p>

## What is BAMP?
**BAMP** (**B**rew+**A**pache+**M**ongoDB+**P**HP) is a small macOS utility to manage your local server based on Apache + MongoDB + PHP using the Homebrew toolkit.

The tool assumes that you have installed PHP using Homebrew. 

> Apache and MongoDB are not required to be installed using Homebrew, but I recomend to install them using homebrew.

## Download
It is free and open source. Download the last version [here](https://github.com/xEsk/BAMP/releases).

## Why BAMP if there is MAMP, XAMP, etc...?
I have been using MAMP for years now, but I don't like to wait others to update so I prefere use my own server setup (and I love how homebrew do its job).

## Required tools
You only need to have installed the [Homebrew](https://brew.sh/) in your system (if you are already not using it, don't lose time reading this and install it!).

## Installation
To install MongoDB: ``brew install mongodb``

[Follow those instructions about how to install Apache and multiple PHP versions in your system](https://getgrav.org/blog/macos-sierra-apache-multiple-php-versions). 

Remember to configure your php.ini and maybe some configs in httpd.conf.

If you will control your Apache with BAMP, the **PHP Switcher Script** is not required, BAMP is a PHP Switcher!

## Troubleshootings
I'm sure at 99% that your PHP code will not run on your first try, and your fancy php code ``<?php echo "Hello world!";`` will be printed in screen instead of your message. Well, maybe it is because you missed to tell apache how to run PHP code. In **httpd.conf** append ``AddType application/x-httpd-php .php`` in ``<IfModule mime_module>`` section.

Oh! Why **index.php** is not working! You missed to tell Apache to recognise index.php! In **httpd.conf** search **IfModule dir_module** and add index.php.
Example:``<IfModule dir_module> DirectoryIndex index.html index.php</IfModule>``

The mongodb extension on macOS High Sierra is not working! To fix this headache follow [those instructions](https://github.com/Homebrew/homebrew-core/issues/21475#issuecomment-352155715).

## How to use BAMP
Just push the **ON** button and Apache will run up. Push **OFF** and Apach will stop.

You can change at any time the PHP to use in your Apache, simple select one PHP version and tachan!

Also you can configure multiple DocumentsRoot and select one of them at any time.

The server will continue running up, even when BAMP is not running! What does it means? You don't need BAMP keept open to use your server! ;)

## Special considerations
The apache is started up using ``sudo apachectl start``, so if you restart your computer you will need to start Apache again.

The MongoDB server will be started-up automatically, but if an instance of mongod is already running when starting Apache, then BAMP will not manage the start-stop of mongod! 

## Icon credits
The icon is based on [icons8 parrot icon](https://icons8.com/icon/36840/parrot)!
