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
  config.vm.box = "bento/ubuntu-24.04"  # ARM64 version for Apple Silicon
  
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

    sudo python3 -m pip install --upgrade pip --break-system-packages
    sudo python3 -m pip install requests --break-system-packages

    # Install Nim 2.2.4 via choosenim
    curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y

    # Switch to Nim 2.2.4
    export PATH="$HOME/.nimble/bin:$PATH"
    choosenim 2.2.4

    # Install nim-gdb for debugging
    mkdir -p $HOME/.nimble/tools
    curl https://raw.githubusercontent.com/nim-lang/Nim/v2.2.4/bin/nim-gdb --output $HOME/.nimble/tools/nim-gdb
    curl https://raw.githubusercontent.com/nim-lang/Nim/v2.2.4/tools/nim-gdb.py --output $HOME/.nimble/tools/nim-gdb.py
    chmod a+x $HOME/.nimble/tools/nim-gdb

    # Update bashrc
    echo 'export PATH="$HOME/bin:$HOME/.nimble/bin:$HOME/.nimble/tools:$PATH"' >> $HOME/.bashrc
    echo "cd #{APP_DIR}" >> $HOME/.bashrc

    echo "==========================================="
    echo "Vagrant setup complete!"
    echo "Ubuntu 24.04 with Nim 2.2.4 installed"
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
