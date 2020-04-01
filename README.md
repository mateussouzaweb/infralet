# Infralet

Whatever you do, infralet it!

## Install

```bash
sudo cp infralet.sh /usr/local/bin/infralet
sudo chmod +x /usr/local/bin/infralet
```

## Usage

```bash
cd path/to/project

# Create if not exists
touch variables.env

# Install a module
infralet install mysql

# Upgrade a module
infralet upgrade nginx

# See help usage
infralet help
```
