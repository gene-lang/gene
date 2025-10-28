# -*- mode: ruby -*-
# vi: set ft=ruby :

APP_DIR = "/vagrant"

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://atlas.hashicorp.com/search.
  # Note: Ubuntu 24.04 ARM64 boxes are not yet widely available for VirtualBox
  # Using Ubuntu 22.04 which has good ARM64 support
  config.vm.box = "bento/ubuntu-22.04"  # ARM64 version for Apple Silicon
  
  # Disable vbguest plugin which causes issues
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
  end

  config.ssh.forward_x11 = true

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  config.vm.provider "virtualbox" do |vb|
    vb.name = "gene-dev"

    # Forward GDB port
    # config.vm.network "forwarded_port", guest: 1234, host: 1234

    # Customize the amount of memory on the VM:
    vb.memory = "3072"
    vb.cpus = 2  # Use 2 CPUs for better performance
    # vb.gui = true
    
    # Performance optimizations
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    
    # VirtualBox 7.1 compatibility fixes
    vb.customize ["modifyvm", :id, "--paravirtprovider", "default"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
  end

  config.vm.network "private_network", type: "dhcp"

  # Install rust osdev toolkit and some standard utilities
  # these run as user vagrant instead of root
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    set -e  # Exit on error
    
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get autoremove -y
    sudo apt-get install -y build-essential
    sudo apt-get install -y gdb
    sudo apt-get install -y llvm lldb
    sudo apt-get install python3 python3-dev python3-pip -y
    sudo apt-get install -y vim git nasm
    #sudo apt-get install xorriso -y
    sudo apt-get install -y texinfo flex bison libncurses-dev
    sudo apt-get install -y cmake libssl-dev

    # Install linux-tools which contains perf
    sudo apt-get install -y linux-tools-generic linux-tools-common

    sudo apt-get install -y valgrind
    # GUI packages moved to optional provisioner below
    sudo apt-get install -y kcachegrind

    # Install pip packages (Ubuntu 22.04 doesn't need --break-system-packages)
    sudo python3 -m pip install --upgrade pip
    sudo python3 -m pip install requests

    # Build Nim 2.2.4 from source (choosenim has SSL issues with corporate proxy)
    echo "Building Nim 2.2.4 from source..."

    # Download Nim 2.2.4 source
    cd /tmp
    wget --no-check-certificate https://github.com/nim-lang/Nim/archive/refs/tags/v2.2.4.tar.gz
    tar xzf v2.2.4.tar.gz
    cd Nim-2.2.4

    # Build Nim compiler
    sh build_all.sh

    # Install to /usr/local
    sudo cp -r bin /usr/local/nim-2.2.4
    sudo ln -sf /usr/local/nim-2.2.4/nim /usr/local/bin/nim
    sudo ln -sf /usr/local/nim-2.2.4/nimble /usr/local/bin/nimble
    sudo ln -sf /usr/local/nim-2.2.4/nimsuggest /usr/local/bin/nimsuggest

    # Copy nim-gdb for debugging
    sudo mkdir -p /usr/local/share/nim
    sudo cp bin/nim-gdb /usr/local/share/nim/
    sudo cp tools/nim-gdb.py /usr/local/share/nim/
    sudo chmod a+x /usr/local/share/nim/nim-gdb
    sudo ln -sf /usr/local/share/nim/nim-gdb /usr/local/bin/nim-gdb

    # Clean up
    cd /tmp
    rm -rf Nim-2.2.4 v2.2.4.tar.gz

    # Update bashrc
    echo 'export PATH="/usr/local/bin:$HOME/.nimble/bin:$PATH"' >> $HOME/.bashrc
    echo "cd #{APP_DIR}" >> $HOME/.bashrc

    echo "==========================================="
    echo "Vagrant setup complete!"
    echo "Ubuntu 22.04 with Nim 2.2.4 installed"
    echo "Working directory: #{APP_DIR}"
    echo "Run 'vagrant ssh' to connect"
    echo "==========================================="
  SHELL
  
  # Optional GUI provisioning (run with: vagrant provision --provision-with gui)
  config.vm.provision "gui", type: "shell", privileged: false, run: "never", inline: <<-SHELL
    sudo apt-get install -y xfce4 virtualbox-guest-dkms virtualbox-guest-utils virtualbox-guest-x11
    echo "GUI installed. Set vb.gui = true and run 'vagrant reload'"
  SHELL

  # config.vm.synced_folder "", APP_DIR, type: "nfs"
  # If above does not work, run this command:
  # sudo mount 192.168.56.3:/Users/gcao/proj/gene /vagrant
end
