# Infralet

Whatever you do, infralet it!

This project was created to help sysadmins execute server tasks without the pain of be lost on the Linux filesystem. Keep everything in one place and infralet it!

The project goes to the complete opposite of the container trend mainly because:

- Containers and orchestration are complex to setup.
- There are too many dark sides that nobody tell you.
- There is much more room to improve yet.
- You already know how to setup a VM.
- You need something simple.

Infralet is ready to go without any learning curve. In fact, it is just a helper to create and maintain your scripts.

## Install & Upgrade

From repository:

```bash
sudo wget https://raw.githubusercontent.com/mateussouzaweb/infralet/master/infralet.sh -O /usr/local/bin/infralet
sudo chmod +x /usr/local/bin/infralet
```

From source:

```bash
git clone https://github.com/mateussouzaweb/infralet.git && cd infralet
sudo cp infralet.sh /usr/local/bin/infralet
sudo chmod +x /usr/local/bin/infralet
```

## Usage

After you create your module (see below), simply run the necessary command:

```bash
cd path/to/project

# Install the module
infralet run module/install

# Upgrade the module
infralet run module/upgrade

# See usage help
infralet help
```

## Module Definition

Each module is a folder that contains a set of files:

```bash
# ls /path/to/sample-module

install.infra # The install file for the module
upgrade.infra # The upgrade file for the module
variables.env # The environment variables used at install and upgrade this module. It also works a bucket to your secrets
```

You can write any shell script into these files to process your module. See the ``samples/`` folder to get a few examples.
